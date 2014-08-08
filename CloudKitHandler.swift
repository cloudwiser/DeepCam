//
//  CloudKitHandler.swift
//  DeepCam
//
//  Created by Nick on 31/07/2014.
//
//

import Foundation
import UIKit
import CloudKit

let kPredictorRecordType = "predictor"

func oldloadData(query: NSMetadataQuery) -> UIDocument
{
    var doc: UIDocument
    
    // (4) iCloud: the heart of the load mechanism: if texts was found, open it and put it into _document; if not create it an then put it into _document
    if (query.resultCount == 1)
    {
        // found the file in iCloud
        let item: AnyObject! = query.resultAtIndex(0)
        let url = item.valueForAttribute(NSMetadataItemURLKey) as NSURL
        
        doc = UIDocument(fileURL: url)
        // _document = doc;
        // doc.delegate = self.viewController;
        // self.viewController.document = doc;
        
        doc.openWithCompletionHandler({success in
            if (success) {
                NSLog("loadData: existing document opened from iCloud")
            } else {
                NSLog("loadData: existing document failed to open from iCloud")
            }
        })
    } else {
        // Nothing in iCloud: create a container for file and give it URL
        NSLog("loadData: document not found in iCloud")
        
        let ubiq: NSURL = NSFileManager.defaultManager().URLForUbiquityContainerIdentifier(nil)
        let ubiquitousPackage: NSURL = ubiq.URLByAppendingPathComponent("Documents").URLByAppendingPathComponent("text.txt")
        
        doc = UIDocument(fileURL: ubiquitousPackage)
        //_document = doc;
        // doc.delegate = self.viewController;
        // self.viewController.document = doc;
        
        doc.saveToURL(doc.fileURL, forSaveOperation: UIDocumentSaveOperation.ForCreating,
            completionHandler: {success in
                    NSLog("loadData: new document save to iCloud")
                    doc.openWithCompletionHandler({success in
                        NSLog("loadData: new document opened from iCloud")
                    })
            })
    }
    return doc
}

func oldqueryDidFinishGathering(notification: NSNotification)
{
    // (3) if Query is finished, this will send the result (i.e. either it found our text.dat or it didn't) to the next function
    let query = notification.object as NSMetadataQuery
    query.disableUpdates()
    query.stopQuery()
    
    var doc = loadData(query)
    
    NSNotificationCenter.defaultCenter().removeObserver(nil, name:NSMetadataQueryDidFinishGatheringNotification, object:query)
}

func oldloadDocument()
{
    // (2) iCloud query: Looks if there exists a file called text.txt in the cloud

    var query = NSMetadataQuery()
    //SCOPE
    // query.searchScopes.append(NSMetadataQueryUbiquitousDocumentsScope)
    //PREDICATE
    var pred = NSPredicate(format: "%K == %@", argumentArray: [NSMetadataItemFSNameKey, "text.txt"])
    query.predicate = pred
    //FINISHED?
    NSNotificationCenter.defaultCenter().addObserver(nil, selector: "queryDidFinishGathering:", name:NSMetadataQueryDidFinishGatheringNotification, object:query)
    query.startQuery()
}
    

//func moveFileToiCloud(fileToMove: FileRepresentation)
//{
//    let sourceURL = fileToMove.url
//    let destinationFileName = fileToMove.fileName;
//    let destinationURL = self.documentsDir.URLByAppendingPathComponent(destinationFileName)
//    
//    var q_default = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
//    dispatch_async(q_default, () {
//        let fileManager : NSFileManager
//        var error: NSError = nil
//        let success = fileManager.setUbiquitous(true, itemAtURL:sourceURL, destinationURL: destinationURL, error:error)
//        let q_main = dispatch_get_main_queue();
//        dispatch_async(q_main, () {
//            if (success) {
//                let fileRepresentation = FileRepresentation(initWithFileName:fileToMove.fileName url:destinationURL)
//                _fileList.removeObject(fileToMove)
//                _fileList.addObject(fileRepresentation)
//                NSLog("moved file to cloud: \(fileRepresentation)")
//            }
//            else {
//                NSLog("Couldn't move file to iCloud: \(fileToMove)")
//            }
//        })
//    })
//}


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





