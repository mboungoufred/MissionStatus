// -----------------------------------------------------------------------
// createTestData.apex
// Creates 200 Accounts and 500 Contacts for testing purposes.
//
// Run with:
//   sf apex run --file scripts/apex/createTestData.apex --target-org <alias>
// -----------------------------------------------------------------------

// 1. Create 200 Accounts
List<Account> accounts = new List<Account>();
for (Integer i = 1; i <= 200; i++) {
    accounts.add(new Account(
        Name            = 'Test Company ' + i,
        MissionStatus__c = 'active'
    ));
}
insert accounts;
System.debug('✓ Inserted ' + accounts.size() + ' accounts.');

// 2. Create 500 Contacts distributed across the 200 accounts (round-robin)
//    Each account receives 2 or 3 contacts.
List<Contact> contacts = new List<Contact>();
for (Integer i = 1; i <= 500; i++) {
    contacts.add(new Contact(
        FirstName    = 'Contact',
        LastName     = 'Test ' + i,
        AccountId    = accounts[Math.mod(i - 1, 200)].Id,
        IsActive__c  = true
    ));
}
insert contacts;
System.debug('✓ Inserted ' + contacts.size() + ' contacts.');

// 3. Add a second account relationship for the first 100 contacts
//    so those contacts are linked to 2 accounts — useful for testing
//    the "not all accounts canceled" branch of the trigger.
List<AccountContactRelation> extraRelations = new List<AccountContactRelation>();
for (Integer i = 0; i < 100; i++) {
    // link contact i to the account at position (i + 100) to avoid duplicates
    extraRelations.add(new AccountContactRelation(
        ContactId = contacts[i].Id,
        AccountId = accounts[i + 100].Id
    ));
}
insert extraRelations;
System.debug('✓ Inserted ' + extraRelations.size() + ' extra AccountContactRelation records.');

System.debug('Data setup complete.');
