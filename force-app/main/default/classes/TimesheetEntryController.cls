public with sharing class TimesheetEntryController {
    
    @AuraEnabled(cacheable=true)
    public static List<Contact> getContactsWithPlacements() {
        try {
            return [
                SELECT Id, Name 
                FROM Contact 
                WHERE Id IN (
                    SELECT bpats__ATS_Candidate__c 
                    FROM bpats__Placement__c 
                    WHERE (bpats__Estimated_End_Date__c >= TODAY OR bpats__Estimated_End_Date__c = null)
                ) 
                AND RecordType.Name = 'Candidate'
                ORDER BY Name
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving contacts: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<bpats__Placement__c> getPlacementsForContact(Id contactId) {
        try {
            return [
                SELECT Id, Name, bpats__Account__r.Name, Billing_Profile__c,
                       bpats__Account__c, bpats__ATS_Job__c
                FROM bpats__Placement__c 
                WHERE bpats__ATS_Candidate__c = :contactId 
                AND (bpats__Estimated_End_Date__c >= TODAY OR bpats__Estimated_End_Date__c = null)
                ORDER BY Name
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving placements: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, String> getBillingProfileLabels(Id placementId) {
        try {
            bpats__Placement__c placement = [
                SELECT Billing_Profile__r.Custom_Field_1_Label__c,
                       Billing_Profile__r.Custom_Field_2_Label__c,
                       Billing_Profile__r.Custom_Field_3_Label__c,
                       Billing_Profile__r.Custom_Field_4_Label__c,
                       Billing_Profile__r.Custom_Field_5_Label__c
                FROM bpats__Placement__c 
                WHERE Id = :placementId
                LIMIT 1
            ];
            
            Map<String, String> labels = new Map<String, String>();
            if (placement.Billing_Profile__c != null) {
                labels.put('customField1', placement.Billing_Profile__r.Custom_Field_1_Label__c);
                labels.put('customField2', placement.Billing_Profile__r.Custom_Field_2_Label__c);
                labels.put('customField3', placement.Billing_Profile__r.Custom_Field_3_Label__c);
                labels.put('customField4', placement.Billing_Profile__r.Custom_Field_4_Label__c);
                labels.put('customField5', placement.Billing_Profile__r.Custom_Field_5_Label__c);
            }
            
            return labels;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving billing profile labels: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Timesheet_Field_Mapping__mdt> getFieldMappings() {
        try {
            return [
                SELECT Source_Column_Name__c, Target_Field_API_Name__c, 
                       Object_Type__c, Client_Name__c, Is_Required__c
                FROM Timesheet_Field_Mapping__mdt
                ORDER BY Client_Name__c, Source_Column_Name__c
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving field mappings: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static TimesheetProcessResult saveTimesheetData(Id contactId, Id placementId, List<TimeEntryData> timeEntries) {
        TimesheetProcessResult result = new TimesheetProcessResult();
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Get placement details
            bpats__Placement__c placement = [
                SELECT Id, bpats__ATS_Candidate__c, bpats__Account__c, bpats__ATS_Job__c,
                       bpats__ATS_Job__r.Name, Billing_Profile__c
                FROM bpats__Placement__c 
                WHERE Id = :placementId
                LIMIT 1
            ];
            
            // Create Timesheet
            ASYMBL_Time__Timesheet__c timesheet = new ASYMBL_Time__Timesheet__c();
            timesheet.ASYMBL_Time__Candidate__c = contactId;
            timesheet.Placement__c = placementId;
            timesheet.ASYMBL_Time__Status__c = 'Approved';
            // timesheet.Proofing_Status__c = 'Needs Proofing'; // This field may not exist
            
            // Calculate pay period dates
            Date earliestDate = null;
            Date latestDate = null;
            for (TimeEntryData entry : timeEntries) {
                Date entryDate = Date.valueOf(entry.dateValue);
                if (earliestDate == null || entryDate < earliestDate) {
                    earliestDate = entryDate;
                }
                if (latestDate == null || entryDate > latestDate) {
                    latestDate = entryDate;
                }
            }
            
            timesheet.ASYMBL_Time__Pay_Period_Start_Date__c = earliestDate;
            timesheet.ASYMBL_Time__Pay_Period_End_Date__c = latestDate;
            
            insert timesheet;
            
            // Create Time Entries
            List<ASYMBL_Time__Time_Entry__c> timeEntriesToInsert = new List<ASYMBL_Time__Time_Entry__c>();
            
            for (TimeEntryData entryData : timeEntries) {
                ASYMBL_Time__Time_Entry__c timeEntry = new ASYMBL_Time__Time_Entry__c();
                timeEntry.ASYMBL_Time__Timesheet__c = timesheet.Id;
                timeEntry.ASYMBL_Time__Date__c = Date.valueOf(entryData.dateValue);
                timeEntry.ASYMBL_Time__Regular_Hours__c = entryData.regularHours;
                timeEntry.ASYMBL_Time__Overtime_Hours__c = entryData.overtimeHours;
                timeEntry.ASYMBL_Time__Double_Time_Hours__c = entryData.doubleTimeHours;
                
                // Map additional hour types to custom fields for now
                // timeEntry.Per_Diem_Pay__c = entryData.sickHours; // Temporary mapping - Field may not exist
                // timeEntry.Per_Diem_Bill__c = entryData.ptoHours; // Temporary mapping - Field may not exist
                
                // Custom fields
                timeEntry.Custom_Field_1__c = entryData.customField1;
                timeEntry.Custom_Field_2__c = entryData.customField2;
                timeEntry.Custom_Field_3__c = entryData.customField3;
                timeEntry.Custom_Field_4__c = entryData.customField4;
                timeEntry.Custom_Field_5__c = entryData.customField5;
                
                timeEntriesToInsert.add(timeEntry);
            }
            
            insert timeEntriesToInsert;
            
            result.success = true;
            result.recordsCreated = timeEntriesToInsert.size();
            result.timesheetId = timesheet.Id;
            
        } catch (Exception e) {
            Database.rollback(sp);
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        
        return result;
    }
    
    @AuraEnabled
    public static TimesheetProcessResult processTimesheetFile(Id contentVersionId) {
        TimesheetProcessResult result = new TimesheetProcessResult();
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Get file content
            ContentVersion cv = [
                SELECT VersionData, Title, FileExtension 
                FROM ContentVersion 
                WHERE Id = :contentVersionId
                LIMIT 1
            ];
            
            String fileContent = cv.VersionData.toString();
            List<String> lines = fileContent.split('\n');
            
            if (lines.isEmpty()) {
                result.success = false;
                result.errorMessage = 'File is empty';
                return result;
            }
            
            // Parse header row to identify columns
            String[] headers = lines[0].split(',');
            Map<String, Integer> headerToIndexMap = new Map<String, Integer>();
            
            for (Integer i = 0; i < headers.size(); i++) {
                String header = headers[i].trim();
                headerToIndexMap.put(header.toLowerCase(), i);
            }
            
            // Validate required headers
            if (!headerToIndexMap.containsKey('employee name') && !headerToIndexMap.containsKey('name')) {
                result.success = false;
                result.errorMessage = 'Missing required column: Employee Name or Name';
                return result;
            }
            
            // Process data rows
            List<TimeEntryData> processedEntries = new List<TimeEntryData>();
            Set<String> contactNamesInFile = new Set<String>();
            
            for (Integer i = 1; i < lines.size(); i++) {
                String[] values = lines[i].split(',');
                if (values.size() < headers.size()) continue;
                
                TimeEntryData entry = parseFileRow(values, headerToIndexMap);
                if (entry != null) {
                    processedEntries.add(entry);
                    contactNamesInFile.add(entry.contactName);
                }
            }
            
            if (processedEntries.isEmpty()) {
                result.success = false;
                result.errorMessage = 'No valid time entry data found in file';
                return result;
            }
            
            // Find contacts in system based on file data
            Map<String, Contact> nameToContactMap = findContactsByNames(contactNamesInFile);
            if (nameToContactMap.isEmpty()) {
                result.success = false;
                result.errorMessage = 'No matching contacts found in system for names in file';
                return result;
            }
            
            // Group entries by contact and process each
            Map<Id, List<TimeEntryData>> contactToEntriesMap = new Map<Id, List<TimeEntryData>>();
            for (TimeEntryData entry : processedEntries) {
                Contact contact = nameToContactMap.get(entry.contactName.toLowerCase());
                if (contact != null) {
                    entry.contactId = contact.Id;
                    if (!contactToEntriesMap.containsKey(contact.Id)) {
                        contactToEntriesMap.put(contact.Id, new List<TimeEntryData>());
                    }
                    contactToEntriesMap.get(contact.Id).add(entry);
                }
            }
            
            Integer totalRecordsCreated = 0;
            List<String> errors = new List<String>();
            
            // Process each contact's time entries
            for (Id contactId : contactToEntriesMap.keySet()) {
                try {
                    List<TimeEntryData> contactEntries = contactToEntriesMap.get(contactId);
                    TimesheetProcessResult contactResult = processContactTimeEntries(contactId, contactEntries);
                    
                    if (contactResult.success) {
                        totalRecordsCreated += contactResult.recordsCreated;
                    } else {
                        errors.add('Contact ' + contactId + ': ' + contactResult.errorMessage);
                    }
                } catch (Exception e) {
                    errors.add('Contact ' + contactId + ': ' + e.getMessage());
                }
            }
            
            if (errors.isEmpty()) {
                result.success = true;
                result.recordsCreated = totalRecordsCreated;
                result.errorMessage = 'Successfully processed ' + totalRecordsCreated + ' time entries for ' + contactToEntriesMap.size() + ' contacts';
            } else {
                if (totalRecordsCreated > 0) {
                    result.success = true; // Partial success
                    result.recordsCreated = totalRecordsCreated;
                    result.errorMessage = 'Partially successful. Created ' + totalRecordsCreated + ' records. Errors: ' + String.join(errors, '; ');
                } else {
                    Database.rollback(sp);
                    result.success = false;
                    result.recordsCreated = 0;
                    result.errorMessage = String.join(errors, '; ');
                }
            }
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        
        return result;
    }
    
    // New methods for updated file processing logic
    private static TimeEntryData parseFileRow(String[] values, Map<String, Integer> headerToIndexMap) {
        TimeEntryData entry = new TimeEntryData();
        
        try {
            // Get employee name
            Integer nameIndex = headerToIndexMap.get('employee name');
            if (nameIndex == null) nameIndex = headerToIndexMap.get('name');
            if (nameIndex != null && nameIndex < values.size()) {
                entry.contactName = values[nameIndex].trim();
            }
            
            // Get date
            Integer dateIndex = headerToIndexMap.get('date');
            if (dateIndex != null && dateIndex < values.size()) {
                entry.dateValue = values[dateIndex].trim();
            }
            
            // Get RT (Regular Time) hours
            Integer rtIndex = headerToIndexMap.get('rt');
            if (rtIndex == null) rtIndex = headerToIndexMap.get('regular hours');
            if (rtIndex != null && rtIndex < values.size() && !String.isEmpty(values[rtIndex].trim())) {
                entry.regularHours = Decimal.valueOf(values[rtIndex].trim());
            }
            
            // Get OT (Overtime) hours
            Integer otIndex = headerToIndexMap.get('ot');
            if (otIndex == null) otIndex = headerToIndexMap.get('overtime hours');
            if (otIndex != null && otIndex < values.size() && !String.isEmpty(values[otIndex].trim())) {
                entry.overtimeHours = Decimal.valueOf(values[otIndex].trim());
            }
            
            // Get DT (Double Time) hours
            Integer dtIndex = headerToIndexMap.get('dt');
            if (dtIndex == null) dtIndex = headerToIndexMap.get('double time hours');
            if (dtIndex != null && dtIndex < values.size() && !String.isEmpty(values[dtIndex].trim())) {
                entry.doubleTimeHours = Decimal.valueOf(values[dtIndex].trim());
            }
            
            // Get Custom Field 1
            Integer cf1Index = headerToIndexMap.get('custom field 1');
            if (cf1Index != null && cf1Index < values.size()) {
                entry.customField1 = values[cf1Index].trim();
            }
            
            // Get Custom Field 2
            Integer cf2Index = headerToIndexMap.get('custom field 2');
            if (cf2Index != null && cf2Index < values.size()) {
                entry.customField2 = values[cf2Index].trim();
            }
            
            // Skip entries with only per diem data (no RT, OT, DT hours)
            if ((entry.regularHours == null || entry.regularHours == 0) &&
                (entry.overtimeHours == null || entry.overtimeHours == 0) &&
                (entry.doubleTimeHours == null || entry.doubleTimeHours == 0)) {
                return null; // Skip this entry
            }
            
            // Validate required fields
            if (String.isEmpty(entry.contactName) || String.isEmpty(entry.dateValue)) {
                return null; // Skip invalid entries
            }
            
            return entry;
            
        } catch (Exception e) {
            System.debug('Error parsing row: ' + e.getMessage());
            return null;
        }
    }
    
    private static Map<String, Contact> findContactsByNames(Set<String> contactNames) {
        Map<String, Contact> nameToContactMap = new Map<String, Contact>();
        
        // Build dynamic SOQL to find contacts by name variations
        List<String> nameConditions = new List<String>();
        for (String name : contactNames) {
            nameConditions.add('Name = \'' + String.escapeSingleQuotes(name) + '\'');
            // Also try with first and last name
            String[] nameParts = name.split(' ');
            if (nameParts.size() >= 2) {
                nameConditions.add('(FirstName = \'' + String.escapeSingleQuotes(nameParts[0]) + 
                                 '\' AND LastName = \'' + String.escapeSingleQuotes(nameParts[nameParts.size()-1]) + '\')');
            }
        }
        
        String soql = 'SELECT Id, Name, FirstName, LastName FROM Contact WHERE RecordType.Name = \'Candidate\' AND (' + 
                     String.join(nameConditions, ' OR ') + ')';
        
        List<Contact> contacts = Database.query(soql);
        
        for (Contact contact : contacts) {
            // Map both full name and individual name parts
            nameToContactMap.put(contact.Name.toLowerCase(), contact);
            
            // Also map original names from file
            for (String fileName : contactNames) {
                if (contact.Name.equalsIgnoreCase(fileName)) {
                    nameToContactMap.put(fileName.toLowerCase(), contact);
                }
            }
        }
        
        return nameToContactMap;
    }
    
    private static TimesheetProcessResult processContactTimeEntries(Id contactId, List<TimeEntryData> timeEntries) {
        TimesheetProcessResult result = new TimesheetProcessResult();
        
        try {
            // Find active placement for contact
            List<bpats__Placement__c> placements = [
                SELECT Id, bpats__ATS_Candidate__c, bpats__Account__c, bpats__ATS_Job__c,
                       bpats__ATS_Job__r.Name, Billing_Profile__c
                FROM bpats__Placement__c 
                WHERE bpats__ATS_Candidate__c = :contactId 
                AND (bpats__Estimated_End_Date__c >= TODAY OR bpats__Estimated_End_Date__c = null)
                ORDER BY bpats__Estimated_End_Date__c DESC NULLS FIRST
                LIMIT 1
            ];
            
            if (placements.isEmpty()) {
                result.success = false;
                result.errorMessage = 'No active placement found for contact';
                return result;
            }
            
            bpats__Placement__c placement = placements[0];
            
            // Calculate Monday to Sunday week period for the time entries
            Date firstDate = Date.valueOf(timeEntries[0].dateValue);
            Date weekStartDate = getWeekStartDate(firstDate);
            Date weekEndDate = weekStartDate.addDays(6);
            
            // Find or create timesheet for this week period in "New" status
            List<ASYMBL_Time__Timesheet__c> existingTimesheets = [
                SELECT Id, ASYMBL_Time__Status__c, ASYMBL_Time__Timesheet_Approver__c
                FROM ASYMBL_Time__Timesheet__c
                WHERE ASYMBL_Time__Candidate__c = :contactId
                AND Placement__c = :placement.Id
                AND ASYMBL_Time__Pay_Period_Start_Date__c = :weekStartDate
                AND ASYMBL_Time__Pay_Period_End_Date__c = :weekEndDate
                LIMIT 1
            ];
            
            ASYMBL_Time__Timesheet__c timesheet;
            if (!existingTimesheets.isEmpty()) {
                timesheet = existingTimesheets[0];
                // Update status to "New" if it's not already
                if (timesheet.ASYMBL_Time__Status__c != 'New') {
                    timesheet.ASYMBL_Time__Status__c = 'New';
                    update timesheet;
                }
            } else {
                // Create new timesheet
                timesheet = new ASYMBL_Time__Timesheet__c();
                timesheet.ASYMBL_Time__Candidate__c = contactId;
                timesheet.Placement__c = placement.Id;
                timesheet.ASYMBL_Time__Status__c = 'New';
                timesheet.ASYMBL_Time__Pay_Period_Start_Date__c = weekStartDate;
                timesheet.ASYMBL_Time__Pay_Period_End_Date__c = weekEndDate;
                insert timesheet;
            }
            
            // Delete existing time entries for this timesheet to avoid duplicates
            delete [SELECT Id FROM ASYMBL_Time__Time_Entry__c WHERE ASYMBL_Time__Timesheet__c = :timesheet.Id];
            
            // Create time entries
            List<ASYMBL_Time__Time_Entry__c> timeEntriesToInsert = new List<ASYMBL_Time__Time_Entry__c>();
            String approverName = null;
            
            for (TimeEntryData entryData : timeEntries) {
                ASYMBL_Time__Time_Entry__c timeEntry = new ASYMBL_Time__Time_Entry__c();
                timeEntry.ASYMBL_Time__Timesheet__c = timesheet.Id;
                timeEntry.ASYMBL_Time__Date__c = Date.valueOf(entryData.dateValue);
                timeEntry.ASYMBL_Time__Regular_Hours__c = entryData.regularHours;
                timeEntry.ASYMBL_Time__Overtime_Hours__c = entryData.overtimeHours;
                timeEntry.ASYMBL_Time__Double_Time_Hours__c = entryData.doubleTimeHours;
                
                // Custom fields
                timeEntry.Custom_Field_1__c = entryData.customField1;
                timeEntry.Custom_Field_2__c = entryData.customField2;
                
                // Extract approver name from Custom Field 2 if present
                if (!String.isEmpty(entryData.customField2) && approverName == null) {
                    approverName = entryData.customField2;
                }
                
                timeEntriesToInsert.add(timeEntry);
            }
            
            insert timeEntriesToInsert;
            
            // Update timesheet with approver name if found
            // Note: For this implementation, we'll store the approver name in Custom Field 2 
            // In a real implementation, you might want to create a text field or find/create a User record
            if (!String.isEmpty(approverName)) {
                // timesheet.ASYMBL_Time__Timesheet_Approver__c = approverUserId; 
                // Would need to find User by name or create a text field for approver name
                System.debug('Approver name found: ' + approverName);
                // Could update a custom text field here if created
            }
            
            result.success = true;
            result.recordsCreated = timeEntriesToInsert.size();
            result.timesheetId = timesheet.Id;
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        
        return result;
    }
    
    private static Date getWeekStartDate(Date inputDate) {
        // Get the Monday of the week containing the input date
        Date monday = inputDate.toStartOfWeek().addDays(1); // Sunday + 1 = Monday
        return monday;
    }
    
    private static Map<String, Id> getContactNameToIdMap() {
        Map<String, Id> nameToIdMap = new Map<String, Id>();
        List<Contact> contacts = [
            SELECT Id, Name 
            FROM Contact 
            WHERE RecordType.Name = 'Candidate'
        ];
        
        for (Contact c : contacts) {
            nameToIdMap.put(c.Name, c.Id);
        }
        
        return nameToIdMap;
    }
    
    // Wrapper classes
    public class TimesheetProcessResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Integer recordsCreated;
        @AuraEnabled public Id timesheetId;
    }
    
    public class TimeEntryData {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String dateValue;
        @AuraEnabled public Decimal regularHours = 0;
        @AuraEnabled public Decimal overtimeHours = 0;
        @AuraEnabled public Decimal doubleTimeHours = 0;
        @AuraEnabled public Decimal sickHours = 0;
        @AuraEnabled public Decimal ptoHours = 0;
        @AuraEnabled public Decimal holidayHours = 0;
        @AuraEnabled public String customField1 = '';
        @AuraEnabled public String customField2 = '';
        @AuraEnabled public String customField3 = '';
        @AuraEnabled public String customField4 = '';
        @AuraEnabled public String customField5 = '';
    }
}