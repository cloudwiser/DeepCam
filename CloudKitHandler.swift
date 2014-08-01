//
//  CloudKitHandler.swift
//  DeepCam
//
//  Created by Nick on 31/07/2014.
//
//

import Foundation
import CloudKit

let kPredictorRecordType = "predictor"

func addCKRecordOfType(recordType: NSString, key: NSString, value: CKRecordValue)
{
    // Create record to save predictors
    let record = CKRecord(recordType: recordType)
    
    // Save the value for key
    record.setObject(value, forKey: key)
    
    // Create the private database for the user to save their data to
    var database = CKContainer.defaultContainer().privateCloudDatabase
    
        // Save the data to the database for the record: task
        func recordSaved(record: CKRecord?, error: NSError?)
        {
            if error {
                // handle it
                NSLog("error: \(error) @ key: \(key)")
            }
        }
    
    // Save data to the database for the record: task
    database.saveRecord(record, completionHandler: recordSaved)
}

func fetchCKRecordsOfType(recordType: NSString) -> NSMutableArray
{
    var records: NSMutableArray = NSMutableArray()
    var items: [CKRecord] = []
    
    // Create the query to load the tasks
    let query = CKQuery(recordType: recordType, predicate: NSPredicate(format: "TRUEPREDICATE"))
    let queryOperation = CKQueryOperation(query: query)
    
        // Fetch the items for the record
        func fetched(record: CKRecord!) {
            items.append(record)
        }
    
    queryOperation.recordFetchedBlock = fetched
    
        // Finish fetching the items for the record
        func fetchFinished(cursor: CKQueryCursor?, error: NSError?)
        {
            if error != nil {
                NSLog("error: \(error)")
            }
            
            // Add contents of the item array to the tasks array
            records.addObjectsFromArray(items)
        }
    
    queryOperation.queryCompletionBlock = fetchFinished
    
    // Create the database you will retreive information from
    let database = CKContainer.defaultContainer().privateCloudDatabase
    
    database.addOperation(queryOperation)
    
    return records
}


func deleteCKRecordsOfType(recordType: NSString)
{
    var items: [CKRecord] = []
    
    // Create the query to load the tasks
    let query = CKQuery(recordType: recordType, predicate: NSPredicate(format: "TRUEPREDICATE"))
    let queryOperation = CKQueryOperation(query: query)
    
        // Fetch the items for the record
        func fetched(record: CKRecord!)
        {
            items.append(record)
        }
    
    queryOperation.recordFetchedBlock = fetched
    
        // Finish fetching the items for the record
        func fetchFinished(cursor: CKQueryCursor?, error: NSError?)
        {
            if error != nil {
                NSLog("error: \(error)")
            }

            // Iterate through the array content ids
            var ids : [CKRecordID] = []
            for i in items {
                ids.append(i.recordID)
            }
            
            // Create the database where you will delete your data from
            let database = CKContainer.defaultContainer().privateCloudDatabase
            // Delete the data from the database using the ids we iterated through
            let clear = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
            
            database.addOperation(clear)
        }
    
    queryOperation.queryCompletionBlock = fetchFinished
    
    // Create the database where you will retreive your new data from
    let database = CKContainer.defaultContainer().privateCloudDatabase
    
    database.addOperation(queryOperation)
}





