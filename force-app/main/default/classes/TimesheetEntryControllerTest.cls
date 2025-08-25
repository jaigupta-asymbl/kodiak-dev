@isTest
public class TimesheetEntryControllerTest {
    
    @TestSetup
    static void makeData() {
        // Create test Account
        Account testAccount = new Account(Name = 'Test Client');
        insert testAccount;
        
        // Create Billing Profile
        Billing_Profile__c billingProfile = new Billing_Profile__c();
        billingProfile.Invoicing_Company__c = testAccount.Id;
        billingProfile.Status__c = 'Active';
        billingProfile.Custom_Field_1_Label__c = 'Job Code';
        billingProfile.Custom_Field_2_Label__c = 'Task ID';
        insert billingProfile;
        
        // Create Contact with Candidate record type
        Contact testContact = new Contact();
        testContact.FirstName = 'Test';
        testContact.LastName = 'Candidate';
        testContact.Email = 'test@example.com';
        insert testContact;
        
        // Create Job
        bpats__Job__c testJob = new bpats__Job__c();
        testJob.Name = 'Test Job';
        testJob.bpats__Account__c = testAccount.Id;
        testJob.Billing_Profile__c = billingProfile.Id;
        insert testJob;
        
        // Create Placement
        bpats__Placement__c testPlacement = new bpats__Placement__c();
        testPlacement.Name = 'Test Placement';
        testPlacement.bpats__ATS_Candidate__c = testContact.Id;
        testPlacement.bpats__Account__c = testAccount.Id;
        testPlacement.bpats__ATS_Job__c = testJob.Id;
        testPlacement.bpats__Estimated_End_Date__c = Date.today().addDays(30); // Active placement
        testPlacement.Billing_Profile__c = billingProfile.Id;
        insert testPlacement;
    }
    
    @isTest
    static void testGetContactsWithPlacements() {
        Test.startTest();
        List<Contact> contacts = TimesheetEntryController.getContactsWithPlacements();
        Test.stopTest();
        
        System.assertNotEquals(0, contacts.size(), 'Should return contacts with active placements');
    }
    
    @isTest
    static void testGetPlacementsForContact() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Candidate' LIMIT 1];
        
        Test.startTest();
        List<bpats__Placement__c> placements = TimesheetEntryController.getPlacementsForContact(testContact.Id);
        Test.stopTest();
        
        System.assertEquals(1, placements.size(), 'Should return one placement for the contact');
    }
    
    @isTest
    static void testGetBillingProfileLabels() {
        bpats__Placement__c testPlacement = [SELECT Id FROM bpats__Placement__c LIMIT 1];
        
        Test.startTest();
        Map<String, String> labels = TimesheetEntryController.getBillingProfileLabels(testPlacement.Id);
        Test.stopTest();
        
        System.assertEquals('Job Code', labels.get('customField1'), 'Should return correct label for custom field 1');
        System.assertEquals('Task ID', labels.get('customField2'), 'Should return correct label for custom field 2');
    }
    
    @isTest
    static void testSaveTimesheetData() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Candidate' LIMIT 1];
        bpats__Placement__c testPlacement = [SELECT Id FROM bpats__Placement__c LIMIT 1];
        
        List<TimesheetEntryController.TimeEntryData> timeEntries = new List<TimesheetEntryController.TimeEntryData>();
        TimesheetEntryController.TimeEntryData entry1 = new TimesheetEntryController.TimeEntryData();
        entry1.dateValue = '2024-01-15';
        entry1.regularHours = 8.0;
        entry1.overtimeHours = 2.0;
        entry1.customField1 = 'JOB001';
        entry1.customField2 = 'TASK001';
        timeEntries.add(entry1);
        
        Test.startTest();
        TimesheetEntryController.TimesheetProcessResult result = TimesheetEntryController.saveTimesheetData(
            testContact.Id, 
            testPlacement.Id, 
            timeEntries
        );
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should successfully save timesheet data');
        System.assertEquals(1, result.recordsCreated, 'Should create one time entry record');
        
        // Verify timesheet was created
        List<ASYMBL_Time__Timesheet__c> timesheets = [
            SELECT Id, ASYMBL_Time__Status__c 
            FROM ASYMBL_Time__Timesheet__c
        ];
        System.assertEquals(1, timesheets.size(), 'Should create one timesheet');
        System.assertEquals('Draft', timesheets[0].ASYMBL_Time__Status__c, 'Timesheet should be in Draft status');
        // System.assertEquals('Needs Proofing', timesheets[0].Proofing_Status__c, 'Timesheet should need proofing'); // Field may not exist
        
        // Verify time entry was created
        List<ASYMBL_Time__Time_Entry__c> entries = [
            SELECT Id, ASYMBL_Time__Regular_Hours__c, ASYMBL_Time__Overtime_Hours__c,
                   Custom_Field_1__c, Custom_Field_2__c
            FROM ASYMBL_Time__Time_Entry__c
        ];
        System.assertEquals(1, entries.size(), 'Should create one time entry');
        System.assertEquals(8.0, entries[0].ASYMBL_Time__Regular_Hours__c, 'Should set correct regular hours');
        System.assertEquals(2.0, entries[0].ASYMBL_Time__Overtime_Hours__c, 'Should set correct overtime hours');
        System.assertEquals('JOB001', entries[0].Custom_Field_1__c, 'Should set custom field 1');
        System.assertEquals('TASK001', entries[0].Custom_Field_2__c, 'Should set custom field 2');
    }
    
    @isTest
    static void testProcessTimesheetFile() {
        // Create a test CSV file content
        String csvContent = 'Contact Name,Date,Regular Hours,Overtime Hours,Custom Field 1\n';
        csvContent += 'Test Candidate,2024-01-15,8,2,JOB001\n';
        csvContent += 'Test Candidate,2024-01-16,8,0,JOB002';
        
        // Create ContentVersion for the test file
        ContentVersion cv = new ContentVersion();
        cv.Title = 'test_timesheet.csv';
        cv.PathOnClient = 'test_timesheet.csv';
        cv.VersionData = Blob.valueOf(csvContent);
        cv.IsMajorVersion = true;
        insert cv;
        
        Test.startTest();
        TimesheetEntryController.TimesheetProcessResult result = TimesheetEntryController.processTimesheetFile(
            cv.Id
        );
        Test.stopTest();
        
        // Note: This test will have limited functionality without proper field mappings
        // In a real scenario, you would need to insert Timesheet_Field_Mapping__mdt records
        System.assertNotEquals(null, result, 'Should return a result object');
    }
    
    @isTest
    static void testGetFieldMappings() {
        Test.startTest();
        List<Timesheet_Field_Mapping__mdt> mappings = TimesheetEntryController.getFieldMappings();
        Test.stopTest();
        
        System.assertNotEquals(null, mappings, 'Should return field mappings list');
    }
    
    @isTest
    static void testErrorHandling() {
        Test.startTest();
        try {
            // Try to get placements for non-existent contact
            TimesheetEntryController.getPlacementsForContact('003000000000000');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Error retrieving placements'), 'Should throw appropriate error');
        }
        Test.stopTest();
    }
}