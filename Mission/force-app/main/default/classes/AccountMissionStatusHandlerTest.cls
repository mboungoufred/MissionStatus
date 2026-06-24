@isTest
public class AccountMissionStatusHandlerTest {

    // -------------------------------------------------------------------
    // HTTP mock — always returns the configured status code
    // -------------------------------------------------------------------
    private class ContactSyncMock implements HttpCalloutMock {
        private Integer code;
        public ContactSyncMock(Integer code) { this.code = code; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody('OK');
            return res;
        }
    }

    // -------------------------------------------------------------------
    // Shared test data
    //
    //  Company A  (active)   ← Contact One   (A only)
    //  Company B  (active)   ← Contact Two   (A + B)
    //  Company C  (canceled) ← Contact Three (A + C)
    // -------------------------------------------------------------------
    @TestSetup
    static void makeData() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Company A', MissionStatus__c = 'active'),
            new Account(Name = 'Company B', MissionStatus__c = 'active'),
            new Account(Name = 'Company C', MissionStatus__c = 'canceled')
        };
        insert accounts;

        // Setting AccountId creates the primary ACR automatically
        List<Contact> contacts = new List<Contact>{
            new Contact(LastName = 'Contact One',   AccountId = accounts[0].Id, IsActive__c = true),
            new Contact(LastName = 'Contact Two',   AccountId = accounts[0].Id, IsActive__c = true),
            new Contact(LastName = 'Contact Three', AccountId = accounts[0].Id, IsActive__c = true)
        };
        insert contacts;

        // Extra account relationships
        insert new List<AccountContactRelation>{
            new AccountContactRelation(AccountId = accounts[1].Id, ContactId = contacts[1].Id),
            new AccountContactRelation(AccountId = accounts[2].Id, ContactId = contacts[2].Id)
        };
    }

    // -------------------------------------------------------------------
    // a. MissionCanceledDate__c
    // -------------------------------------------------------------------

    @isTest
    static void testCanceledDateSetOnFirstCancellation() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));
        Account acc = [SELECT Id FROM Account WHERE Name = 'Company A'];

        Test.startTest();
        acc.MissionStatus__c = 'canceled';
        update acc;
        Test.stopTest();

        System.assertEquals(
            Date.today(),
            [SELECT MissionCanceledDate__c FROM Account WHERE Id = :acc.Id].MissionCanceledDate__c,
            'MissionCanceledDate__c should be set to today when transitioning to canceled'
        );
    }

    @isTest
    static void testCanceledDateNotOverwrittenWhenAlreadyCanceled() {
        // Company C is already canceled — set a past date, then update again without changing status
        Account acc = [SELECT Id FROM Account WHERE Name = 'Company C'];
        Date pastDate = Date.today().addDays(-10);
        acc.MissionCanceledDate__c = pastDate;
        update acc;

        Test.startTest();
        acc.MissionStatus__c = 'canceled'; // no status change
        update acc;
        Test.stopTest();

        System.assertEquals(
            pastDate,
            [SELECT MissionCanceledDate__c FROM Account WHERE Id = :acc.Id].MissionCanceledDate__c,
            'MissionCanceledDate__c should not be touched if the status was already canceled'
        );
    }

    // -------------------------------------------------------------------
    // b. Contact deactivation logic
    // -------------------------------------------------------------------

    @isTest
    static void testContactDeactivatedWhenSoleAccountCanceled() {
        // Contact One is linked only to Company A → canceling A should deactivate it
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));
        Account accA = [SELECT Id FROM Account WHERE Name = 'Company A'];

        Test.startTest();
        accA.MissionStatus__c = 'canceled';
        update accA;
        Test.stopTest();

        System.assertEquals(
            false,
            [SELECT IsActive__c FROM Contact WHERE LastName = 'Contact One'].IsActive__c,
            'Contact One should be inactive: its only account is now canceled'
        );
    }

    @isTest
    static void testContactStaysActiveWhenOneAccountStillActive() {
        // Contact Two is linked to Company A and Company B — canceling only A keeps it active
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));
        Account accA = [SELECT Id FROM Account WHERE Name = 'Company A'];

        Test.startTest();
        accA.MissionStatus__c = 'canceled';
        update accA;
        Test.stopTest();

        System.assertEquals(
            true,
            [SELECT IsActive__c FROM Contact WHERE LastName = 'Contact Two'].IsActive__c,
            'Contact Two should remain active: Company B is still active'
        );
    }

    @isTest
    static void testContactDeactivatedWhenLastActiveAccountCanceled() {
        // Contact Three is linked to Company A (active) and Company C (already canceled)
        // Canceling Company A means ALL accounts are now canceled → contact becomes inactive
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));
        Account accA = [SELECT Id FROM Account WHERE Name = 'Company A'];

        Test.startTest();
        accA.MissionStatus__c = 'canceled';
        update accA;
        Test.stopTest();

        System.assertEquals(
            false,
            [SELECT IsActive__c FROM Contact WHERE LastName = 'Contact Three'].IsActive__c,
            'Contact Three should be inactive: both linked accounts are now canceled'
        );
    }

    @isTest
    static void testAlreadyInactiveContactIsSkipped() {
        // An already-inactive contact should not trigger a redundant DML or sync
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        Account acc = new Account(Name = 'Solo Company', MissionStatus__c = 'active');
        insert acc;
        Contact inactive = new Contact(LastName = 'Already Inactive', AccountId = acc.Id, IsActive__c = false);
        insert inactive;

        Test.startTest();
        acc.MissionStatus__c = 'canceled';
        update acc;
        Test.stopTest();

        System.assertEquals(
            false,
            [SELECT IsActive__c FROM Contact WHERE Id = :inactive.Id].IsActive__c,
            'Already-inactive contact should remain false with no error'
        );
    }

    @isTest
    static void testNoContactsLinkedToAccount() {
        // Canceling an account with no contacts should not throw any error
        Account acc = new Account(Name = 'Orphan Company', MissionStatus__c = 'active');
        insert acc;

        Test.startTest();
        acc.MissionStatus__c = 'canceled';
        update acc;
        Test.stopTest();

        System.assertEquals(
            Date.today(),
            [SELECT MissionCanceledDate__c FROM Account WHERE Id = :acc.Id].MissionCanceledDate__c,
            'MissionCanceledDate__c should still be set even when no contacts are linked'
        );
    }

    // -------------------------------------------------------------------
    // Bulk safety — 200 accounts
    // -------------------------------------------------------------------

    @isTest
    static void testBulkCancellation200Accounts() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        List<Account> bulkAccounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            bulkAccounts.add(new Account(Name = 'Bulk Co ' + i, MissionStatus__c = 'active'));
        }
        insert bulkAccounts;

        List<Contact> bulkContacts = new List<Contact>();
        for (Integer i = 0; i < 200; i++) {
            bulkContacts.add(new Contact(LastName = 'Bulk Contact ' + i, AccountId = bulkAccounts[i].Id, IsActive__c = true));
        }
        insert bulkContacts;

        Test.startTest();
        for (Account acc : bulkAccounts) {
            acc.MissionStatus__c = 'canceled';
        }
        update bulkAccounts;
        Test.stopTest();

        for (Account acc : [SELECT MissionCanceledDate__c FROM Account WHERE Id IN :bulkAccounts]) {
            System.assertEquals(Date.today(), acc.MissionCanceledDate__c,
                'Every bulk account should have MissionCanceledDate__c set');
        }

        for (Contact c : [SELECT IsActive__c FROM Contact WHERE Id IN :bulkContacts]) {
            System.assertEquals(false, c.IsActive__c,
                'Every bulk contact should be deactivated');
        }
    }
}
