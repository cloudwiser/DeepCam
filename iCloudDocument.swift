//
//  iCloudDocument.swift
//  DeepCam
//
//  Created by Nick Hall on 08/08/2014.
//  Copyright (c) 2014 cloudwise.co
//

import Foundation
import UIKit

@objc class iCloudDocument: UIDocument {
    
    var fileContent: NSString = ""
    
    init(fileURL url: NSURL!, content fileContent: NSString) {
        super.init(fileURL: url)
        self.fileContent = fileContent
    }

    // Called whenever the application reads data from the file system
    override func loadFromContents(contents: AnyObject!, ofType typeName: String!, error outError: NSErrorPointer) -> Bool
    {
        if (contents.length > 0) {
            self.fileContent = NSString(bytes: contents.bytes, length:contents.length, encoding: NSUTF8StringEncoding)
        } else {
            // When the note is first created, assign some default content
            self.fileContent = "Empty"
        }
        return true
    }
    
    override func contentsForType(typeName: String!, error outError: NSErrorPointer) -> AnyObject!
    {
    
        if (self.fileContent.length == 0) {
            self.fileContent = "Empty"
        }
        return NSData(bytes: self.fileContent.UTF8String, length: self.fileContent.length)
    }
    
    func objectiveCTestFunc () {
    
    }
}


func swiftLoadDocument()
{
    var query = NSMetadataQuery()
    
    // set the scope
    query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    // define the predicate
    var pred = NSPredicate(format: "%K == %@", argumentArray: [NSMetadataItemFSNameKey, "text.txt"])
    query.predicate = pred
    // add the Finished notification
    NSNotificationCenter.defaultCenter().addObserver(nil, selector: "queryDidFinishGathering:", name:NSMetadataQueryDidFinishGatheringNotification, object:query)
    query.startQuery()
}


func swiftqueryDidFinishGathering(notification: NSNotification)
{
    let query = notification.object as NSMetadataQuery
    query.disableUpdates()
    query.stopQuery()
    
    var doc = swiftLoadData(query)
    
    NSNotificationCenter.defaultCenter().removeObserver(nil, name:NSMetadataQueryDidFinishGatheringNotification, object:query)
}


func swiftLoadData(query: NSMetadataQuery) -> UIDocument
{
    var doc: UIDocument
    
    // If the file was found, open it and return. If not found then create it and return...
    if (query.resultCount == 1)
    {
        // found the file in iCloud
        let item: AnyObject! = query.resultAtIndex(0)
        let url = item.valueForAttribute(NSMetadataItemURLKey) as NSURL
        
        doc = UIDocument(fileURL: url)
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






