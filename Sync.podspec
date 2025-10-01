Pod::Spec.new do |s|
s.name             = "Sync"
s.version          = "6.5.0"
s.summary          = "Modern Swift JSON synchronization to Core Data"
s.description      = <<-DESC
**Sync** eases your everyday job of parsing a `JSON` response and getting it into Core Data. It uses a convention-over-configuration paradigm to facilitate your workflow.

* Automatic mapping of CamelCase or snake_case JSON into Core Data
* Handles operations in safe background threads
* Thread-safe saving, we handle retrieving and storing objects in the right threads
* Diffing of changes, updated, inserted and deleted objects (which are automatically purged for you)
* Auto-mapping of relationships (one-to-one, one-to-many and many-to-many)
* Smart-updates, only updates your `NSManagedObject`s if the server values are different (useful when using `NSFetchedResultsController` delegates)
* Uniquing, Core Data does this based on `objectID`s, we use your primary key (such as `id`) for this
DESC
s.homepage         = "https://github.com/3lvis/Sync"
s.license          = 'MIT'
s.author           = { "Elvis Nuñez" => "elvisnunez@me.com" }
s.source           = { :git => "https://github.com/3lvis/Sync.git", :tag => s.version.to_s }
s.social_media_url = "https://twitter.com/3lvis"
 */
contract GarageManager {
    mapping(address => Car[]) private garages;

    struct Car {
        string make;
        string model;
        string color;
        uint numberOfDoors;
    }

    error BadCarIndex(uint256 index);


s.ios.deployment_target = '11.0'
s.osx.deployment_target = '10.15'
s.watchos.deployment_target = '5.0'
s.tvos.deployment_target = '11.0'
s.requires_arc = true
s.source_files = 'Source/**/*'
s.swift_version = '5.0'
s.frameworks = 'Foundation', 'CoreData'
end
