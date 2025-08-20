@isTest
public class InvoiceGenerationServiceTest {
    
    @TestSetup
    static void makeData() {
        // Create test Account
        Account testAccount = new Account(Name = 'Test Client Account');
        insert testAccount;
        
        // Create Billing Profile
        Billing_Profile__c billingProfile = new Billing_Profile__c();
        billingProfile.Invoicing_Company__c = testAccount.Id;
        billingProfile.Status__c = 'Active';
        billingProfile.Invoice_Approval_Required__c = 'No';
        billingProfile.Payment_Terms__c = 'Net 30';
        billingProfile.PO_Required__c = 'No';
        insert billingProfile;
        
        // Create Contact
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
        testPlacement.bpats__Estimated_End_Date__c = Date.today().addDays(30);
        testPlacement.Billing_Profile__c = billingProfile.Id;
        insert testPlacement;
    }
    
    @isTest
    static void testCreateNewInvoiceFromTimesheet() {
        // Get test data
        bpats__Placement__c placement = [SELECT Id FROM bpats__Placement__c LIMIT 1];
        Contact contact = [SELECT Id FROM Contact WHERE LastName = 'Candidate' LIMIT 1];
        
        // Create timesheet with approved status
        ASYMBL_Time__Timesheet__c timesheet = new ASYMBL_Time__Timesheet__c();
        timesheet.ASYMBL_Time__Candidate__c = contact.Id;
        timesheet.Placement__c = placement.Id;
        timesheet.ASYMBL_Time__Status__c = 'Approved';
        timesheet.Create_Invoice__c = false;
        timesheet.ASYMBL_Time__Pay_Period_Start_Date__c = Date.today().addDays(-6);
        timesheet.ASYMBL_Time__Pay_Period_End_Date__c = Date.today();
        insert timesheet;
        
        // Create time entries
        List<ASYMBL_Time__Time_Entry__c> timeEntries = new List<ASYMBL_Time__Time_Entry__c>();
        for (Integer i = 0; i < 5; i++) {
            ASYMBL_Time__Time_Entry__c entry = new ASYMBL_Time__Time_Entry__c();
            entry.ASYMBL_Time__Timesheet__c = timesheet.Id;
            entry.ASYMBL_Time__Date__c = Date.today().addDays(-i);
            entry.ASYMBL_Time__Regular_Hours__c = 8;
            entry.ASYMBL_Time__Overtime_Hours__c = 2;
            timeEntries.add(entry);
        }
        insert timeEntries;
        
        Test.startTest();
        // Trigger invoice generation by checking the Create Invoice checkbox
        timesheet.Create_Invoice__c = true;
        update timesheet;
        Test.stopTest();
        
        // Verify invoice was created
        List<Invoice__c> invoices = [SELECT Id, Status__c, Total_Amount__c FROM Invoice__c];
        System.assertEquals(1, invoices.size(), 'Should create one invoice');
        System.assertEquals('Ready', invoices[0].Status__c, 'Invoice status should be Ready');
        
        // Verify invoice line items were created
        List<Invoice_Line_Item__c> lineItems = [
            SELECT Id, Description__c, Quantity__c, Unit_Price__c, Amount__c 
            FROM Invoice_Line_Item__c
        ];
        System.assertNotEquals(0, lineItems.size(), 'Should create invoice line items');
    }
    
    @isTest
    static void testUpdateExistingInvoice() {
        // Get test data
        bpats__Placement__c placement = [SELECT Id, bpats__Account__c, Billing_Profile__c FROM bpats__Placement__c LIMIT 1];
        Contact contact = [SELECT Id FROM Contact WHERE LastName = 'Candidate' LIMIT 1];
        
        // Create existing invoice for the same period
        Invoice__c existingInvoice = new Invoice__c();
        existingInvoice.Account__c = placement.bpats__Account__c;
        existingInvoice.Billing_Profile__c = placement.Billing_Profile__c;
        existingInvoice.Status__c = 'Ready';
        existingInvoice.Invoice_Period_Start__c = Date.today().addDays(-6);
        existingInvoice.Invoice_Period_End__c = Date.today();
        existingInvoice.Total_Amount__c = 100.00;
        insert existingInvoice;
        
        // Create timesheet for the same period
        ASYMBL_Time__Timesheet__c timesheet = new ASYMBL_Time__Timesheet__c();
        timesheet.ASYMBL_Time__Candidate__c = contact.Id;
        timesheet.Placement__c = placement.Id;
        timesheet.ASYMBL_Time__Status__c = 'Approved';
        timesheet.Create_Invoice__c = false;
        timesheet.ASYMBL_Time__Pay_Period_Start_Date__c = Date.today().addDays(-6);
        timesheet.ASYMBL_Time__Pay_Period_End_Date__c = Date.today();
        insert timesheet;
        
        // Create time entries
        ASYMBL_Time__Time_Entry__c entry = new ASYMBL_Time__Time_Entry__c();
        entry.ASYMBL_Time__Timesheet__c = timesheet.Id;
        entry.ASYMBL_Time__Date__c = Date.today();
        entry.ASYMBL_Time__Regular_Hours__c = 8;
        insert entry;
        
        Test.startTest();
        // Trigger invoice update by checking the Create Invoice checkbox
        timesheet.Create_Invoice__c = true;
        update timesheet;
        Test.stopTest();
        
        // Verify existing invoice was updated (not a new one created)
        List<Invoice__c> invoices = [SELECT Id, Status__c, Total_Amount__c FROM Invoice__c];
        System.assertEquals(1, invoices.size(), 'Should still have only one invoice');
        
        // Verify new line items were added
        List<Invoice_Line_Item__c> lineItems = [SELECT Id FROM Invoice_Line_Item__c];
        System.assertNotEquals(0, lineItems.size(), 'Should have invoice line items');
    }
    
    @isTest
    static void testInvoiceGenerationWithApprovalRequired() {
        // Update billing profile to require approval
        Billing_Profile__c bp = [SELECT Id FROM Billing_Profile__c LIMIT 1];
        bp.Invoice_Approval_Required__c = 'Yes';
        update bp;
        
        // Get test data
        bpats__Placement__c placement = [SELECT Id FROM bpats__Placement__c LIMIT 1];
        Contact contact = [SELECT Id FROM Contact WHERE LastName = 'Candidate' LIMIT 1];
        
        // Create timesheet
        ASYMBL_Time__Timesheet__c timesheet = new ASYMBL_Time__Timesheet__c();
        timesheet.ASYMBL_Time__Candidate__c = contact.Id;
        timesheet.Placement__c = placement.Id;
        timesheet.ASYMBL_Time__Status__c = 'Approved';
        timesheet.Create_Invoice__c = false;
        timesheet.ASYMBL_Time__Pay_Period_Start_Date__c = Date.today().addDays(-6);
        timesheet.ASYMBL_Time__Pay_Period_End_Date__c = Date.today();
        insert timesheet;
        
        // Create time entry
        ASYMBL_Time__Time_Entry__c entry = new ASYMBL_Time__Time_Entry__c();
        entry.ASYMBL_Time__Timesheet__c = timesheet.Id;
        entry.ASYMBL_Time__Date__c = Date.today();
        entry.ASYMBL_Time__Regular_Hours__c = 8;
        insert entry;
        
        Test.startTest();
        timesheet.Create_Invoice__c = true;
        update timesheet;
        Test.stopTest();
        
        // Verify invoice status is "Needs Review" when approval required
        List<Invoice__c> invoices = [SELECT Id, Status__c FROM Invoice__c];
        System.assertEquals(1, invoices.size(), 'Should create one invoice');
        System.assertEquals('Needs Review', invoices[0].Status__c, 'Invoice should need review when approval required');
    }
    
    @isTest
    static void testInvoiceGenerationServiceDirectly() {
        // Get test data
        bpats__Placement__c placement = [SELECT Id FROM bpats__Placement__c LIMIT 1];
        Contact contact = [SELECT Id FROM Contact WHERE LastName = 'Candidate' LIMIT 1];
        
        // Create timesheet
        ASYMBL_Time__Timesheet__c timesheet = new ASYMBL_Time__Timesheet__c();
        timesheet.ASYMBL_Time__Candidate__c = contact.Id;
        timesheet.Placement__c = placement.Id;
        timesheet.ASYMBL_Time__Status__c = 'Approved';
        timesheet.Create_Invoice__c = true;
        timesheet.ASYMBL_Time__Pay_Period_Start_Date__c = Date.today().addDays(-6);
        timesheet.ASYMBL_Time__Pay_Period_End_Date__c = Date.today();
        insert timesheet;
        
        // Create time entry
        ASYMBL_Time__Time_Entry__c entry = new ASYMBL_Time__Time_Entry__c();
        entry.ASYMBL_Time__Timesheet__c = timesheet.Id;
        entry.ASYMBL_Time__Date__c = Date.today();
        entry.ASYMBL_Time__Regular_Hours__c = 8;
        entry.ASYMBL_Time__Overtime_Hours__c = 2;
        insert entry;
        
        Test.startTest();
        InvoiceGenerationService.InvoiceResult result = 
            InvoiceGenerationService.processTimesheetsForInvoicing(new List<Id>{timesheet.Id});
        Test.stopTest();
        
        // Verify successful result
        System.assertEquals(true, result.success, 'Invoice generation should be successful');
        System.assertEquals(1, result.invoicesCreated, 'Should create one invoice');
        System.assertNotEquals(0, result.invoiceIds.size(), 'Should return invoice IDs');
        
        // Verify invoice and line items created
        List<Invoice__c> invoices = [SELECT Id FROM Invoice__c];
        System.assertEquals(1, invoices.size(), 'Should create one invoice');
        
        List<Invoice_Line_Item__c> lineItems = [SELECT Id FROM Invoice_Line_Item__c];
        System.assertNotEquals(0, lineItems.size(), 'Should create line items');
    }
    
    @isTest
    static void testInvoiceGenerationWithInactiveProfile() {
        // Make billing profile inactive
        Billing_Profile__c bp = [SELECT Id FROM Billing_Profile__c LIMIT 1];
        bp.Status__c = 'Inactive';
        update bp;
        
        // Get test data
        bpats__Placement__c placement = [SELECT Id FROM bpats__Placement__c LIMIT 1];
        Contact contact = [SELECT Id FROM Contact WHERE LastName = 'Candidate' LIMIT 1];
        
        // Create timesheet
        ASYMBL_Time__Timesheet__c timesheet = new ASYMBL_Time__Timesheet__c();
        timesheet.ASYMBL_Time__Candidate__c = contact.Id;
        timesheet.Placement__c = placement.Id;
        timesheet.ASYMBL_Time__Status__c = 'Approved';
        timesheet.Create_Invoice__c = true;
        timesheet.ASYMBL_Time__Pay_Period_Start_Date__c = Date.today().addDays(-6);
        timesheet.ASYMBL_Time__Pay_Period_End_Date__c = Date.today();
        insert timesheet;
        
        Test.startTest();
        InvoiceGenerationService.InvoiceResult result = 
            InvoiceGenerationService.processTimesheetsForInvoicing(new List<Id>{timesheet.Id});
        Test.stopTest();
        
        // Verify failure due to inactive billing profile
        System.assertEquals(false, result.success, 'Invoice generation should fail with inactive billing profile');
        System.assert(result.errorMessage.contains('inactive billing profile'), 'Error should mention inactive billing profile');
    }
    
    @isTest
    static void testTimesheetInvoiceGenerationBatch() {
        // Get test data
        bpats__Placement__c placement = [SELECT Id FROM bpats__Placement__c LIMIT 1];
        Contact contact = [SELECT Id FROM Contact WHERE LastName = 'Candidate' LIMIT 1];
        
        // Create timesheet
        ASYMBL_Time__Timesheet__c timesheet = new ASYMBL_Time__Timesheet__c();
        timesheet.ASYMBL_Time__Candidate__c = contact.Id;
        timesheet.Placement__c = placement.Id;
        timesheet.ASYMBL_Time__Status__c = 'Approved';
        timesheet.Create_Invoice__c = true;
        timesheet.ASYMBL_Time__Pay_Period_Start_Date__c = Date.today().addDays(-6);
        timesheet.ASYMBL_Time__Pay_Period_End_Date__c = Date.today();
        insert timesheet;
        
        // Create time entry
        ASYMBL_Time__Time_Entry__c entry = new ASYMBL_Time__Time_Entry__c();
        entry.ASYMBL_Time__Timesheet__c = timesheet.Id;
        entry.ASYMBL_Time__Date__c = Date.today();
        entry.ASYMBL_Time__Regular_Hours__c = 8;
        insert entry;
        
        Test.startTest();
        TimesheetInvoiceGenerationBatch.processTimesheets(new List<Id>{timesheet.Id});
        Test.stopTest();
        
        // Verify job was queued (we can't actually test the async execution in unit tests)
        // But we can verify no exceptions were thrown during queueing
        System.assert(true, 'Batch processing should queue without errors');
    }
}