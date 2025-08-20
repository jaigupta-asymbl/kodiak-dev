public class InvoiceCSVExportService {
    
    public class ExportResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String fileName;
        @AuraEnabled public String csvContent;
        @AuraEnabled public Integer invoicesExported;
        
        public ExportResult() {
            this.success = false;
            this.invoicesExported = 0;
        }
    }
    
    public class FieldMapping {
        public String csvHeader;
        public String objectName;
        public String fieldName;
        public String defaultValue;
        public Integer sortOrder;
    }
    
    @AuraEnabled
    public static List<Invoice__c> getFinalizedInvoices() {
        try {
            return [
                SELECT Id, Name, Invoice_Date__c, Total_Amount__c, Status__c,
                       Account__c, Account__r.Name, Account__r.AccountNumber,
                       Billing_Profile__c, Invoice_Due_Date__c, Invoice_Period_Start__c,
                       Invoice_Period_End__c, Cost_Center__c
                FROM Invoice__c 
                WHERE Status__c = 'Finalized' 
                ORDER BY Invoice_Date__c DESC, Name
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving invoices: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static ExportResult exportInvoicesToCSV(List<Id> invoiceIds) {
        ExportResult result = new ExportResult();
        
        try {
            if (invoiceIds == null || invoiceIds.isEmpty()) {
                result.message = 'No invoices selected for export';
                return result;
            }
            
            // Validate all invoices are in Finalized status
            List<Invoice__c> invoices = validateInvoicesForExport(invoiceIds);
            if (invoices.isEmpty()) {
                result.message = 'No valid invoices found for export';
                return result;
            }
            
            // Get field mappings from Custom Metadata
            List<FieldMapping> fieldMappings = getCSVFieldMappings();
            if (fieldMappings.isEmpty()) {
                result.message = 'No CSV field mappings configured';
                return result;
            }
            
            // Generate CSV content
            String csvContent = generateCSVContent(invoices, fieldMappings);
            
            // Update invoice status to Exported
            updateInvoiceStatus(invoices);
            
            // Prepare result
            result.success = true;
            result.csvContent = csvContent;
            result.fileName = 'Kodiak_Invoice_Export_' + 
                             DateTime.now().format('yyyy_MM_dd_HH_mm') + '.csv';
            result.invoicesExported = invoices.size();
            result.message = 'Successfully exported ' + invoices.size() + ' invoices';
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error during export: ' + e.getMessage();
            System.debug('Export error: ' + e.getMessage() + ' - Stack: ' + e.getStackTraceString());
        }
        
        return result;
    }
    
    private static List<Invoice__c> validateInvoicesForExport(List<Id> invoiceIds) {
        return [
            SELECT Id, Name, Invoice_Date__c, Total_Amount__c, Status__c,
                   Account__c, Account__r.Name, Account__r.AccountNumber,
                   Billing_Profile__c, Invoice_Due_Date__c, Invoice_Period_Start__c,
                   Invoice_Period_End__c, Cost_Center__c,
                   (SELECT Id, Name, Description__c, Quantity__c, Unit_Price__c, 
                           Amount__c, Per_Diem_Hours__c, Date_Worked__c
                    FROM Invoice_Line_Items__r)
            FROM Invoice__c 
            WHERE Id IN :invoiceIds 
            AND Status__c = 'Finalized'
        ];
    }
    
    private static List<FieldMapping> getCSVFieldMappings() {
        List<FieldMapping> mappings = new List<FieldMapping>();
        
        for (Invoice_CSV_Field_Mapping__mdt mapping : [
            SELECT MasterLabel, CSV_Column_Header__c, Object_API_Name__c, 
                   Field_API_Name__c, Default_Value__c, Sort_Order__c
            FROM Invoice_CSV_Field_Mapping__mdt 
            WHERE Is_Active__c = true 
            ORDER BY Sort_Order__c ASC
        ]) {
            FieldMapping fm = new FieldMapping();
            fm.csvHeader = mapping.CSV_Column_Header__c;
            fm.objectName = mapping.Object_API_Name__c;
            fm.fieldName = mapping.Field_API_Name__c;
            fm.defaultValue = mapping.Default_Value__c;
            fm.sortOrder = Integer.valueOf(mapping.Sort_Order__c);
            mappings.add(fm);
        }
        
        return mappings;
    }
    
    private static String generateCSVContent(List<Invoice__c> invoices, List<FieldMapping> fieldMappings) {
        List<String> csvLines = new List<String>();
        
        // Generate header row
        List<String> headers = new List<String>();
        for (FieldMapping mapping : fieldMappings) {
            headers.add('"' + mapping.csvHeader + '"');
        }
        csvLines.add(String.join(headers, ','));
        
        // Generate data rows
        Integer sequence = 1;
        for (Invoice__c invoice : invoices) {
            // For each invoice, generate rows for line items
            if (invoice.Invoice_Line_Items__r != null && !invoice.Invoice_Line_Items__r.isEmpty()) {
                for (Invoice_Line_Item__c lineItem : invoice.Invoice_Line_Items__r) {
                    csvLines.add(generateCSVRow(invoice, lineItem, fieldMappings, sequence));
                    sequence++;
                }
            } else {
                // Invoice without line items - create single row
                csvLines.add(generateCSVRow(invoice, null, fieldMappings, sequence));
                sequence++;
            }
        }
        
        return String.join(csvLines, '\n');
    }
    
    private static String generateCSVRow(Invoice__c invoice, Invoice_Line_Item__c lineItem, 
                                        List<FieldMapping> fieldMappings, Integer sequence) {
        List<String> values = new List<String>();
        
        for (FieldMapping mapping : fieldMappings) {
            String value = getFieldValue(invoice, lineItem, mapping, sequence);
            values.add('"' + (value != null ? String.valueOf(value).replace('"', '""') : '') + '"');
        }
        
        return String.join(values, ',');
    }
    
    private static String getFieldValue(Invoice__c invoice, Invoice_Line_Item__c lineItem, 
                                       FieldMapping mapping, Integer sequence) {
        try {
            // Handle special cases first
            if (mapping.fieldName == 'Sequence') {
                return String.valueOf(sequence);
            }
            
            if (mapping.fieldName == 'Static_Value' && mapping.defaultValue != null) {
                return mapping.defaultValue;
            }
            
            // Handle different object types
            SObject sourceObject = null;
            if (mapping.objectName == 'Invoice__c') {
                sourceObject = invoice;
            } else if (mapping.objectName == 'Invoice_Line_Item__c' && lineItem != null) {
                sourceObject = lineItem;
            }
            
            if (sourceObject != null) {
                // Handle related field access (e.g., Account__r.Name)
                if (mapping.fieldName.contains('.')) {
                    return getRelatedFieldValue(sourceObject, mapping.fieldName);
                } else {
                    Object fieldValue = sourceObject.get(mapping.fieldName);
                    return fieldValue != null ? String.valueOf(fieldValue) : mapping.defaultValue;
                }
            }
            
            return mapping.defaultValue;
            
        } catch (Exception e) {
            System.debug('Error getting field value for ' + mapping.fieldName + ': ' + e.getMessage());
            return mapping.defaultValue;
        }
    }
    
    private static String getRelatedFieldValue(SObject sourceObject, String fieldPath) {
        try {
            String[] pathParts = fieldPath.split('\\.');
            SObject currentObject = sourceObject;
            
            for (Integer i = 0; i < pathParts.size() - 1; i++) {
                currentObject = currentObject.getSObject(pathParts[i]);
                if (currentObject == null) {
                    return null;
                }
            }
            
            Object fieldValue = currentObject.get(pathParts[pathParts.size() - 1]);
            return fieldValue != null ? String.valueOf(fieldValue) : null;
            
        } catch (Exception e) {
            System.debug('Error getting related field value: ' + e.getMessage());
            return null;
        }
    }
    
    private static void updateInvoiceStatus(List<Invoice__c> invoices) {
        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        
        for (Invoice__c invoice : invoices) {
            if (invoice.Status__c == 'Finalized') {
                invoice.Status__c = 'Exported';
                invoicesToUpdate.add(invoice);
            }
        }
        
        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
    }
}