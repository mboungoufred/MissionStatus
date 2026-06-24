public class AccountMissionStatusHandler {

    public static void handleBeforeUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        for (Account acc : newAccounts) {
            if (acc.MissionStatus__c == 'canceled' && oldMap.get(acc.Id).MissionStatus__c != 'canceled') {
                acc.MissionCanceledDate__c = Date.today();
            }
        }
    }

    public static void handleAfterUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        // Collect accounts that just transitioned to "canceled"
        Set<Id> newlyCanceledAccountIds = new Set<Id>();
        for (Account acc : newAccounts) {
            if (acc.MissionStatus__c == 'canceled' && oldMap.get(acc.Id).MissionStatus__c != 'canceled') {
                newlyCanceledAccountIds.add(acc.Id);
            }
        }

        if (newlyCanceledAccountIds.isEmpty()) return;

        // Find all contacts linked to these newly canceled accounts
        Set<Id> affectedContactIds = new Set<Id>();
        for (AccountContactRelation rel : [
            SELECT ContactId
            FROM AccountContactRelation
            WHERE AccountId IN :newlyCanceledAccountIds
        ]) {
            affectedContactIds.add(rel.ContactId);
        }

        if (affectedContactIds.isEmpty()) return;

        // For each affected contact, count total accounts vs canceled accounts
        Map<Id, Integer> totalAccountsPerContact   = new Map<Id, Integer>();
        Map<Id, Integer> canceledAccountsPerContact = new Map<Id, Integer>();

        for (AccountContactRelation rel : [
            SELECT ContactId, Account.MissionStatus__c
            FROM AccountContactRelation
            WHERE ContactId IN :affectedContactIds
        ]) {
            Id cId = rel.ContactId;
            if (!totalAccountsPerContact.containsKey(cId)) {
                totalAccountsPerContact.put(cId, 0);
                canceledAccountsPerContact.put(cId, 0);
            }
            totalAccountsPerContact.put(cId, totalAccountsPerContact.get(cId) + 1);
            if (rel.Account.MissionStatus__c == 'canceled') {
                canceledAccountsPerContact.put(cId, canceledAccountsPerContact.get(cId) + 1);
            }
        }

        // Contacts where every linked account is canceled
        Set<Id> fullyInactiveContactIds = new Set<Id>();
        for (Id cId : affectedContactIds) {
            Integer total    = totalAccountsPerContact.get(cId);
            Integer canceled = canceledAccountsPerContact.get(cId);
            if (total != null && total == canceled) {
                fullyInactiveContactIds.add(cId);
            }
        }

        if (fullyInactiveContactIds.isEmpty()) return;

        // Only update contacts that are still active (avoids useless DML)
        List<Contact> contactsToDeactivate = [
            SELECT Id FROM Contact
            WHERE Id IN :fullyInactiveContactIds AND IsActive__c = true
        ];

        if (contactsToDeactivate.isEmpty()) return;

        for (Contact c : contactsToDeactivate) {
            c.IsActive__c = false;
        }
        update contactsToDeactivate;

        // Build payload and sync asynchronously (callout not allowed in DML context)
        List<ContactSyncService.ContactPayload> payload = new List<ContactSyncService.ContactPayload>();
        for (Contact c : contactsToDeactivate) {
            payload.add(new ContactSyncService.ContactPayload(c.Id, false));
        }
        ContactSyncService.syncContacts(JSON.serialize(payload));
    }
}
