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
    public static TimesheetProcessResult processTimesheetFile(Id contentVersionId, String clientName) {
        TimesheetProcessResult result = new TimesheetProcessResult();
        
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
            
            // Get field mappings for the client
            List<Timesheet_Field_Mapping__mdt> mappings = [
                SELECT Source_Column_Name__c, Target_Field_API_Name__c, 
                       Object_Type__c, Is_Required__c
                FROM Timesheet_Field_Mapping__mdt
                WHERE Client_Name__c = :clientName OR Client_Name__c = null
                ORDER BY Client_Name__c DESC NULLS LAST
            ];
            
            Map<String, String> columnToFieldMap = new Map<String, String>();
            for (Timesheet_Field_Mapping__mdt mapping : mappings) {
                columnToFieldMap.put(mapping.Source_Column_Name__c.toLowerCase(), mapping.Target_Field_API_Name__c);
            }
            
            // Parse header row
            String[] headers = lines[0].split(',');
            Map<Integer, String> columnIndexToFieldMap = new Map<Integer, String>();
            
            for (Integer i = 0; i < headers.size(); i++) {
                String header = headers[i].trim().toLowerCase();
                if (columnToFieldMap.containsKey(header)) {
                    columnIndexToFieldMap.put(i, columnToFieldMap.get(header));
                }
            }
            
            // Process data rows
            List<TimeEntryData> timeEntries = new List<TimeEntryData>();
            Map<String, Id> contactNameToIdMap = getContactNameToIdMap();
            
            for (Integer i = 1; i < lines.size(); i++) {
                String[] values = lines[i].split(',');
                if (values.size() < headers.size()) continue;
                
                TimeEntryData entry = new TimeEntryData();
                String contactName = '';
                
                for (Integer j = 0; j < values.size(); j++) {
                    String value = values[j].trim();
                    String fieldName = columnIndexToFieldMap.get(j);
                    
                    if (fieldName == 'Contact_Name') {
                        contactName = value;
                    } else if (fieldName == 'Date') {
                        entry.dateValue = value;
                    } else if (fieldName == 'Regular_Hours') {
                        entry.regularHours = Decimal.valueOf(value);
                    } else if (fieldName == 'Overtime_Hours') {
                        entry.overtimeHours = Decimal.valueOf(value);
                    } else if (fieldName == 'Double_Time_Hours') {
                        entry.doubleTimeHours = Decimal.valueOf(value);
                    } else if (fieldName == 'Custom_Field_1') {
                        entry.customField1 = value;
                    } else if (fieldName == 'Custom_Field_2') {
                        entry.customField2 = value;
                    } else if (fieldName == 'Custom_Field_3') {
                        entry.customField3 = value;
                    } else if (fieldName == 'Custom_Field_4') {
                        entry.customField4 = value;
                    } else if (fieldName == 'Custom_Field_5') {
                        entry.customField5 = value;
                    }
                }
                
                entry.contactId = contactNameToIdMap.get(contactName);
                if (entry.contactId != null) {
                    timeEntries.add(entry);
                }
            }
            
            // Group by contact and create timesheets
            Map<Id, List<TimeEntryData>> contactToEntriesMap = new Map<Id, List<TimeEntryData>>();
            for (TimeEntryData entry : timeEntries) {
                if (!contactToEntriesMap.containsKey(entry.contactId)) {
                    contactToEntriesMap.put(entry.contactId, new List<TimeEntryData>());
                }
                contactToEntriesMap.get(entry.contactId).add(entry);
            }
            
            Integer totalRecords = 0;
            
            // Process each contact's time entries
            for (Id contactId : contactToEntriesMap.keySet()) {
                List<bpats__Placement__c> placements = getPlacementsForContact(contactId);
                if (!placements.isEmpty()) {
                    Id placementId = placements[0].Id; // Use first active placement
                    TimesheetProcessResult tempResult = saveTimesheetData(contactId, placementId, contactToEntriesMap.get(contactId));
                    if (tempResult.success) {
                        totalRecords += tempResult.recordsCreated;
                    }
                }
            }
            
            result.success = true;
            result.recordsCreated = totalRecords;
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        
        return result;
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