//
//  DataStorage.swift
//  DataStorageSwift
//
//  Created by Ivankov Alexey on 04.05.16.
//  Copyright © 2016 Ivankov Alexey. All rights reserved.
//

import Foundation
import CoreData

public protocol IDataStorage : class
{
    func read(readBlock main:@escaping (_ context:NSManagedObjectContext)->[AnyObject]?) ->[AnyObject]?
    
    func save(main:@escaping (_ context:NSManagedObjectContext)->Void, completion:@escaping (_ success:Bool)->Void)
    func save(queue:DispatchQueue, main:@escaping (_ context:NSManagedObjectContext)->Void, completion:@escaping (_ success:Bool)->Void)
    
    func remove(main: @escaping (_ context: NSManagedObjectContext) -> Void, completion: @escaping (_ success: Bool) -> Void)
    func remove(queue: DispatchQueue, main: @escaping (_ context: NSManagedObjectContext) -> Void, completion: @escaping (_ success: Bool) -> Void)
    
    func saveAndWait(main:@escaping (_ context:NSManagedObjectContext)->Void, completion:@escaping (_ success:Bool)->Void)
    func saveAndWait(queue:DispatchQueue, main:@escaping (_ context:NSManagedObjectContext)->Void, completion:@escaping (_ success:Bool)->Void)
    
    func createFetchedController(entityName: String, sortByProperties: [String], ascending: Bool, sectionNameKeyPath:String?) -> NSFetchedResultsController<NSFetchRequestResult>
    
    func createFetchedController(entityName: String, sortByProperties: [String], ascending: Bool, sectionNameKeyPath:String?, predicate:NSPredicate?) -> NSFetchedResultsController<NSFetchRequestResult>
    
    func findObject(entityName: String, objectIdFieldName:String, objectIdvalue:String)-> AnyObject?
    func findFirst(entityName: String)-> AnyObject?
    
    func findAll(entityName: String,objectIdFieldName:String, objectIdvalue:String)-> Array<AnyObject>?
    func findAll(entityName: String, predicate:NSPredicate)-> Array<AnyObject>?
    func findAll(entityName: String) -> Array<AnyObject>?
   
    
    func findObject(entityName: String, predicate:NSPredicate)-> AnyObject?
}


public class DataStorage : IDataStorage
{

	//MARK: 
	internal var dbName:String;
	
	internal var model:NSManagedObjectModel?;
	internal var coordinator:NSPersistentStoreCoordinator? ;
	internal var parentContext:NSManagedObjectContext?;
	private(set) var mainContext:NSManagedObjectContext?;
	
	//MARK: Lazy
	
	private lazy var documentDirectoryURL:NSURL? = {
		return FileManager.default.urls(for: FileManager.SearchPathDirectory.documentDirectory, in: FileManager.SearchPathDomainMask.userDomainMask).last;
	}() as NSURL?
	
	internal lazy var dbURL:NSURL? = {
        
		return self.documentDirectoryURL?.appendingPathComponent(self.dbName +  ".sqlite");
	} () as NSURL?
	
	
	internal lazy var modelURL:NSURL? = {
		return Bundle.main.url(forResource: self.dbName, withExtension: "momd")
	}() as NSURL?
	
	
	public required init(dbName:String)
	{
		self.dbName = dbName;
		self.createCoreDataStack();

	}
	
	private func createCoreDataStack()
	{
		//MARK: init lazy 
		
		self.model = self.createModel();
		
		if (self.checkMigration())
		{
			do
			{
				 try FileManager.default.removeItem(at: self.dbURL! as URL);
			}
			catch
			{
				assertionFailure("migration db failed!!");
			}
		}

		let coordinator:NSPersistentStoreCoordinator? = self.createCoordinator();
		
		if coordinator == nil
		{
			assertionFailure("migration db failed!!");
		}
		else
		{
			self.coordinator = coordinator;
		}
		
		
		self.parentContext = self.createParentContext();
		self.mainContext = self.createMainContext();
		
	}
	
	private func checkMigration() -> Bool
	{
		var isMigration:Bool = false;
		
		let coordinator:NSPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: self.model!);
		let persistentStore:NSPersistentStore? = try? coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: self.dbURL! as URL, options: [NSMigratePersistentStoresAutomaticallyOption:true, NSInferMappingModelAutomaticallyOption:true])
		
		if (persistentStore == nil) {
			isMigration = true;
		}
		
		return isMigration;
	}
	
	//MARK: IDataStorage
	
	public func read(readBlock main:@escaping (_ context:NSManagedObjectContext)->[AnyObject]?) ->[AnyObject]?
	{
		let context:NSManagedObjectContext = Thread.isMainThread == true ? self.mainContext! : self.createReadContext()!;
	
		var data:[AnyObject]? = nil;
		
		context.performAndWait { () -> Void in
			data = main(context);
		};
		
		return data;
	}
	
	
	public func save(main:@escaping (_ context:NSManagedObjectContext)->Void, completion:@escaping (_ success:Bool)->Void)
	{
		let context:NSManagedObjectContext = self.createSaveContext()!;
		
		context.perform { () -> Void in
			main(context);
			context.saveFull(completion: completion);
		}
	}
	
	public func save(queue:DispatchQueue, main:@escaping (_ context:NSManagedObjectContext)->Void, completion:@escaping (_ success:Bool)->Void)
	{
		queue.async() { () -> Void in
			
			self.save(main: main, completion: completion);
		}
	}
	
	
	public func saveAndWait(main:@escaping (_ context:NSManagedObjectContext)->Void, completion:@escaping (_ success:Bool)->Void)
	{
		let context:NSManagedObjectContext = self.createSaveContext()!;
		
		context.performAndWait { () -> Void in
			main(context);
			context.saveFull(completion: completion);
		}
	}
	
	public func saveAndWait(queue:DispatchQueue, main:@escaping (_ context:NSManagedObjectContext)->Void, completion:@escaping (_ success:Bool)->Void)
	{
		queue.async() { () -> Void in
			
			self.saveAndWait(main: main, completion: completion);
		}
	}
    
    public func remove(main: @escaping (_ context: NSManagedObjectContext) -> Void, completion: @escaping (_ success: Bool) -> Void) {
        
        let context:NSManagedObjectContext = Thread.isMainThread == true ? self.mainContext! : self.createSaveContext()!;
        
        context.perform { () -> Void in
            main(context);
            context.saveFull(completion: completion);
        }
    }
    
    public func remove(queue: DispatchQueue, main: @escaping (_ context: NSManagedObjectContext) -> Void, completion: @escaping (_ success: Bool) -> Void) {
        
        queue.async() {
            self.remove(main: main, completion: completion);
        }
    }
    
    public func findObject(entityName: String, objectIdFieldName:String, objectIdvalue:String)-> AnyObject? {
        
        let predicate = NSPredicate(format: "\(objectIdFieldName) == %@", objectIdvalue)
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.returnsObjectsAsFaults = true;
        let items = read { (context) -> [AnyObject]? in
            do {
                let fetchedIssues = try context.fetch(fetchRequest) as! [NSManagedObject]
                if fetchedIssues.first != nil {
                    return fetchedIssues
                }
            } catch {
                print("exception!!!")
            }
            
            return nil
        }
        return items?.first
    }
    
    public func findObject(entityName: String, predicate:NSPredicate)-> AnyObject? {
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.returnsObjectsAsFaults = true;
        let items = read { (context) -> [AnyObject]? in
            do {
                let fetchedIssues = try context.fetch(fetchRequest) as! [NSManagedObject]
                if fetchedIssues.first != nil {
                    return fetchedIssues
                }
            } catch {
                print("exception!!!")
            }
            
            return nil
        }
        return items?.first
    }

    
    public func findFirst(entityName: String) -> AnyObject? {
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.returnsObjectsAsFaults = true;
        let items = read { (context) -> [AnyObject]? in
            do {
                let fetchedIssues = try context.fetch(fetchRequest) as! [NSManagedObject]
                if fetchedIssues.first != nil {
                    return fetchedIssues
                }
            } catch {
                print("exception!!!")
            }
            
            return nil
        }
        return items?.first
    }
    
    public func findAll(entityName: String) -> Array<AnyObject>? {
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.returnsObjectsAsFaults = true;
        let items = read { (context) -> [AnyObject]? in
            do {
                let fetchedIssues = try context.fetch(fetchRequest) as! [NSManagedObject]
                if fetchedIssues.first != nil {
                    return fetchedIssues
                }
            } catch {
                print("exception!!!")
            }
            
            return nil
        }
        return items
    }
    
    public func findAll(entityName: String, objectIdFieldName: String, objectIdvalue: String) -> Array<AnyObject>? {
        
        let predicate = NSPredicate(format: "\(objectIdFieldName) == %@", objectIdvalue)
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.returnsObjectsAsFaults = true;
        let items = read { (context) -> [AnyObject]? in
            do {
                let fetchedIssues = try context.fetch(fetchRequest) as! [NSManagedObject]
                if fetchedIssues.first != nil {
                    return fetchedIssues
                }
            } catch {
                print("exception!!!")
            }
            
            return nil
        }
        return items
    }
    
    public func findAll(entityName: String, predicate:NSPredicate) -> Array<AnyObject>?
    {
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.returnsObjectsAsFaults = true;
        let items = read { (context) -> [AnyObject]? in
            do {
                let fetchedIssues = try context.fetch(fetchRequest) as! [NSManagedObject]
                if fetchedIssues.first != nil {
                    return fetchedIssues
                }
            } catch {
                print("exception!!!")
            }
            
            return nil
        }
        return items
    }
    
    
    public func createFetchedController(entityName: String, sortByProperties: [String], ascending: Bool, sectionNameKeyPath:String? = nil) -> NSFetchedResultsController<NSFetchRequestResult>
    {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        
        var sortDescriptors:[NSSortDescriptor] = [];
        for sortProperty in sortByProperties
        {
            let sortDescriptor = NSSortDescriptor(key: sortProperty, ascending: ascending)
            sortDescriptors.append(sortDescriptor);
        }
        
        fetchRequest.sortDescriptors = sortDescriptors;
       
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: mainContext!, sectionNameKeyPath: sectionNameKeyPath, cacheName: nil)
        return fetchedResultsController
        
    }

    
    public func createFetchedController(entityName: String, sortByProperties: [String], ascending: Bool, sectionNameKeyPath:String? = nil, predicate:NSPredicate? = nil) -> NSFetchedResultsController<NSFetchRequestResult>
    {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        
        var sortDescriptors:[NSSortDescriptor] = [];
        for sortProperty in sortByProperties
        {
            let sortDescriptor = NSSortDescriptor(key: sortProperty, ascending: ascending)
            sortDescriptors.append(sortDescriptor);
        }
        
        fetchRequest.sortDescriptors = sortDescriptors;
        fetchRequest.predicate = predicate;
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: mainContext!, sectionNameKeyPath: sectionNameKeyPath, cacheName: nil)
        return fetchedResultsController
        
    }
    
  

}

extension DataStorage
{
	internal func createModel() -> NSManagedObjectModel?
	{
		return NSManagedObjectModel(contentsOf: self.modelURL! as URL);
	}
	
	internal func createCoordinator() -> NSPersistentStoreCoordinator?
	{
		let coordinator:NSPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: self.model!);
		let persistentStore:NSPersistentStore? = try? coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: self.dbURL! as URL, options: [NSMigratePersistentStoresAutomaticallyOption:true, NSInferMappingModelAutomaticallyOption:true])
		
		if (persistentStore == nil)
		{
			return nil;
		}
		else
		{
			return coordinator;
		}
	}
	
	internal func createParentContext() -> NSManagedObjectContext?
	{
		let context:NSManagedObjectContext = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.privateQueueConcurrencyType);
		context.persistentStoreCoordinator = self.coordinator;
		
		return context;
	}
	
	
	internal func createMainContext() -> NSManagedObjectContext?
	{
		let context:NSManagedObjectContext = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType);
		context.parent = self.parentContext;
		
		return context;
	}
	
	internal func createReadContext() -> NSManagedObjectContext?
	{
		let context:NSManagedObjectContext = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.privateQueueConcurrencyType);
		context.parent = self.mainContext;
		
		return context;
	}
	
	internal func createSaveContext() -> NSManagedObjectContext?
	{
		let context:NSManagedObjectContext = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.privateQueueConcurrencyType);
		context.parent = self.mainContext;
		
		return context;
	}
    
}

extension NSManagedObjectContext
{
	internal func saveFull(completion:@escaping (_ succes:Bool)->Void)
	{
		var currentContext:NSManagedObjectContext? = self;
		
		while(currentContext != nil && currentContext!.hasChanges)
		{
			currentContext!.performAndWait({ () -> Void in
				
				do
				{
					try currentContext!.save();
				}
				catch
				{
					completion(false);
				}
				
				currentContext = currentContext?.parent;
			})
		}
		completion(true);
	}
}
