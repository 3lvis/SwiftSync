**Notice: Sync was supported from it's creation back in 2014 until March 2021**

**If you are starting a new SwiftData app, use SwiftSync instead.** This branch preserves the legacy Core Data implementation of Sync. The SwiftData-era successor is a new codebase and not a drop-in upgrade.

Moving forward I won't be able to support this project since I'm no longer active in making iOS apps with Core Data. I'm leaving this repository as a historical reference of what happened during this time. Sync had in total 130 releases with almost 30 contributors. If you still support this project I encourage you to fork it and continue the development. I don't feel comfortable with passing this project to another developer due to the fact that I want to have some involvement in all the projects that live under my account. 7 years was a good run, thank you everyone for using this project and thank you to everyone that has contributed to it. Best of luck in your careers and in what this constantly evolving tech world has for all of us. 

Initial releases: https://github.com/3lvis/Sync/releases?after=0.4.1

--------------------------------------------------------------------

![Sync](https://raw.githubusercontent.com/3lvis/Sync/master/Images/logo-v3.png)

**Sync** eases your everyday job of parsing a JSON response and syncing it with Core Data. **Sync** is a lightweight Swift library that uses a convention-over-configuration paradigm to facilitate your workflow.

<div align = "center">
  <a href="https://cocoapods.org/pods/Sync">
<img src="https://img.shields.io/cocoapods/v/Sync.svg?style=flat" />
  </a>
  <a href="https://github.com/3lvis/Sync">
    <img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat" />
  </a>
  <a href="https://github.com/3lvis/Sync#installation">
    <img src="https://img.shields.io/badge/compatible-swift%205.0-orange.svg" />
  </a>
</div>

<div align = "center">
  <a href="https://cocoapods.org/pods/Sync" target="blank">
    <img src="https://img.shields.io/cocoapods/p/Sync.svg?style=flat" />
  </a>
  <a href="https://cocoapods.org/pods/Sync" target="blank">
    <img src="https://img.shields.io/cocoapods/l/Sync.svg?style=flat" />
  </a>
  <a href="https://gitter.im/3lvis/Sync">
    <img src="https://img.shields.io/gitter/room/nwjs/nw.js.svg" />
  </a>
  <br>
  <br>
</div>

Syncing JSON to Core Data is a repetitive tasks that often demands adding a lot of boilerplate code. Mapping attributes, mapping relationships, diffing for inserts, removals and updates are often tasks that don't change between apps. Taking this in account we took the challenge to abstract this into a library. **Sync** uses the knowledge of your Core Data model to infer all the mapping between your JSON and Core Data, once you use it, it feels so obvious that you'll wonder why you weren't doing this before.

* Automatic mapping of camelCase or snake_case JSON into Core Data
* Thread-safe saving, we handle retrieving and storing objects in the right threads
* Diffing of changes, updated, inserted and deleted objects (which are automatically purged for you)
* Auto-mapping of relationships (one-to-one, one-to-many and many-to-many)
* Smart-updates, only updates your `NSManagedObject`s if the server values are different from your local ones
* Uniquing, one Core Data entry per primary key
* `NSOperation` subclass, any Sync process can be queued and cancelled at any time!

## Table of Contents

* [Basic example](#basic-example)
* [Demo project](#demo-project)
* [Getting Started](#getting-started)
  * [Core Data Stack](#core-data-stack)
  * [Primary Key](#primary-key)
  * [Attribute Mapping](#attribute-mapping)
  * [Attribute Types](#attribute-types)
  * [Relationship Mapping](#relationship-mapping)
    * [One-to-many](#one-to-many)
    * [One-to-many (simplified)](#one-to-many-simplified)
    * [One-to-one](#one-to-one)
    * [One-to-one (simplified)](#one-to-one-simplified)
  * [JSON Exporting](#json-exporting)
* [FAQ](#faq)
* [Installation](#installation)
* [License](#license)

## Basic example

### Model

![Model](https://raw.githubusercontent.com/3lvis/Sync/master/Images/one-to-many-swift.png)

### JSON

```json
[
  {
    "id": 6,
    "name": "Shawn Merrill",
    "email": "shawn@ovium.com",
    "created_at": "2014-02-14T04:30:10+00:00",
    "updated_at": "2014-02-17T10:01:12+00:00",
    "notes": [
      {
        "id": 0,
        "text": "Shawn Merril's diary, episode 1",
        "created_at": "2014-03-11T19:11:00+00:00",
        "updated_at": "2014-04-18T22:01:00+00:00"
      }
    ]
  }
]
```

### DataStack

DataStack is a wrapper on top of the Core Data boilerplate, it encapsulates dealing with NSPersistentStoreCoordinator and NSManageObjectContexts.

```swift
self.dataStack = DataStack(modelName: "DataModel")
```

[You can find here more ways of initializing your DataStack](https://github.com/3lvis/Sync/blob/6723c1f9a07014024e0f8f2923d1930789cabb72/Source/DataStack/DataStack.swift#L77-L196).

### Sync

```swift
dataStack.sync(json, inEntityNamed: "User") { error in
    // New objects have been inserted
    // Existing objects have been updated
    // And not found objects have been deleted
}
```

Alternatively, if you only want to sync users that have been created in the last 24 hours, you could do this by using a `NSPredicate`.

```swift
let now = NSDate()
let yesterday = now.dateByAddingTimeInterval(-24*60*60)
let predicate = NSPredicate(format:@"createdAt > %@", yesterday)

dataStack.sync(json, inEntityNamed: "User", predicate: predicate) { error in
    //..
}
```

## Demo Project

[We have a simple demo project](/iOSDemo) of how to set up and use Sync to fetch data from the network and display it in a UITableView. The demo project features both [Networking](https://github.com/3lvis/networking) and [Alamofire](https://github.com/Alamofire/Alamofire) as the networking libraries.

### DataStack with Storyboards

Configuring a DataStack with Storyboard is different than doing it via dependency injection here you'll find a sample project in how to achieve this setup.

https://github.com/3lvis/StoryboardDemo

## Getting Started

### Core Data Stack

Replace your Core Data stack with an instance of [DataStack](https://github.com/3lvis/Sync/blob/master/docs/DataStack.md).

```swift
self.dataStack = DataStack(modelName: "Demo")
```

### Primary key

Sync requires your entities to have a primary key, this is important for diffing, otherwise Sync doesn’t know how to differentiate between entries.

By default **Sync** uses `id` from the JSON and `id` (or `remoteID`) from Core Data as the primary key.

You can mark any attribute as primary key by adding `sync.isPrimaryKey` and the value `true` (or `YES`). For example, in our [Designer News](https://github.com/3lvis/DesignerNewsDemo) project we have a `Comment` entity that uses `body` as the primary key.

![Custom primary key](https://raw.githubusercontent.com/3lvis/Sync/master/Images/custom-primary-key-v3.png)

If you add the flag `sync.isPrimaryKey` to the attribute `contractID` then:

- Local primary key will be: `contractID`
- Remote primary key will be: `contract_id`

If you want to use `id` for the remote primary key you also have to add the flag `sync.remoteKey` and write `id` as the value.

- Local primary key will be: `articleBody`
- Remote primary key will be: `id`

### Attribute Mapping

Your attributes should match their JSON counterparts in `camelCase` notation instead of `snake_case`. For example `first_name` in the JSON maps to `firstName` in Core Data and `address` in the JSON maps to `address` in Core Data.

There are some exception to this rule:

* Reserved attributes should be prefixed with the `entityName` (`type` becomes `userType`, `description` becomes `userDescription` and so on). In the JSON they don't need to change, you can keep `type` and `description` for example. A full list of reserved attributes can be found [here](https://github.com/3lvis/Sync/blob/master/Source/PropertyMapper/NSManagedObject%2BPropertyMapperHelpers.m#L282-L284)
* Attributes with acronyms will be normalized (`id`, `pdf`, `url`, `png`, `jpg`, `uri`, `json`, `xml`). For example `user_id` will be mapped to `userID` and so on. You can find the entire list of supported acronyms [here](https://github.com/3lvis/Sync/blob/master/Source/Inflections/Inflections.m#L204-L206).

If you want to map your Core Data attribute with a JSON attribute that has different naming, you can do by adding `sync.remoteKey` in the user info box with the value you want to map.

![Custom remote key](https://raw.githubusercontent.com/3lvis/Sync/master/Images/custom-remote-key-v2.png)

### Attribute Types

#### Array/Dictionary

To map **arrays** or **dictionaries** just set attributes as `Binary Data` on the Core Data modeler.

![screen shot 2015-04-02 at 11 10 11 pm](https://cloud.githubusercontent.com/assets/1088217/6973785/7d3767dc-d98d-11e4-8add-9c9421b5ed47.png)

#### Retrieving mapped arrays

```json
{
  "hobbies": [
    "football",
    "soccer",
    "code"
  ]
}
```

```swift
let hobbies = NSKeyedUnarchiver.unarchiveObjectWithData(managedObject.hobbies) as? [String]
// ==> "football", "soccer", "code"
```

#### Retrieving mapped dictionaries
```json
{
  "expenses" : {
    "cake" : 12.50,
    "juice" : 0.50
  }
}
```

```swift
let expenses = NSKeyedUnarchiver.unarchiveObjectWithData(managedObject.expenses) as? [String: Double]
// ==> "cake" : 12.50, "juice" : 0.50
```

#### Dates

We went for supporting [ISO8601](http://en.wikipedia.org/wiki/ISO_8601) and unix timestamp out of the box because those are the most common formats when parsing dates, also we have a [quite performant way to parse this strings](https://github.com/3lvis/Sync/blob/master/Source/DateParser/NSDate%2BPropertyMapper.m) which overcomes the [performance issues of using `NSDateFormatter`](http://blog.soff.es/how-to-drastically-improve-your-app-with-an-afternoon-and-instruments/).

```swift
let values = ["created_at" : "2014-01-01T00:00:00+00:00",
              "updated_at" : "2014-01-02",
              "published_at": "1441843200"
              "number_of_attendes": 20]

managedObject.fill(values)

let createdAt = managedObject.value(forKey: "createdAt")
// ==> "2014-01-01 00:00:00 +00:00"

let updatedAt = managedObject.value(forKey: "updatedAt")
// ==> "2014-01-02 00:00:00 +00:00"

let publishedAt = managedObject.value(forKey: "publishedAt")
// ==> "2015-09-10 00:00:00 +00:00"
```

### Relationship mapping

**Sync** will map your relationships to their JSON counterparts. In the [Example](#example-with-snake_case-in-swift) presented at the beginning of this document you can see a very basic example of relationship mapping.

#### One-to-many

Lets consider the following Core Data model.

![One-to-many](https://raw.githubusercontent.com/3lvis/Sync/master/Images/one-to-many-swift.png)

This model has a one-to-many relationship between `User` and `Note`, so in other words a user has many notes. Here can also find an inverse relationship to user on the Note model. This is required for Sync to have more context on how your models are presented. Finally, in the Core Data model there is a cascade relationship between user and note, so when a user is deleted all the notes linked to that user are also removed (you can specify any delete rule).

So when Sync, looks into the following JSON, it will sync all the notes for that specific user, doing the necessary inverse relationship dance.

```json
[
  {
    "id": 6,
    "name": "Shawn Merrill",
    "notes": [
      {
        "id": 0,
        "text": "Shawn Merril's diary, episode 1",
      }
    ]
  }
]
```

#### One-to-many Simplified

As you can see this procedures require the full JSON object to be included, but when working with APIs, sometimes you already have synced all the required items. Sync supports this too.

For example, in the one-to-many example, you have a user, that has many notes. If you already have synced all the notes then your JSON would only need the `notes_ids`, this can be an array of strings or integers. As a side-note only do this if you are 100% sure that all the required items (notes) have been synced, otherwise this relationships will get ignored and an error will be logged. Also if you want to remove all the notes from a user, just provide `"notes_ids": null` and **Sync** will do the clean up for you.

```json
[
  {
    "id": 6,
    "name": "Shawn Merrill",
    "notes_ids": [0, 1, 2]
  }
]
```

#### One-to-one

A similar procedure is applied to one-to-one relationships. For example lets say you have the following model:

![one-to-one](https://raw.githubusercontent.com/3lvis/Sync/master/Images/one-to-one-v2.png)

This model is simple, a user as a company. A compatible JSON would look like this:

```json
[
  {
    "id": 6,
    "name": "Shawn Merrill",
    "company": {
      "id": 0,
      "text": "Facebook",
    }
  }
]
```

#### One-to-one Simplified

As you can see this procedures require the full JSON object to be included, but when working with APIs, sometimes you already have synced all the required items. Sync supports this too.

For example, in the one-to-one example, you have a user, that has one company. If you already have synced all the companies then your JSON would only need the `company_id`. As a sidenote only do this if you are 100% sure that all the required items (companies) have been synced, otherwise this relationships will get ignored and an error will be logged. Also if you want to remove the company from the user, just provide `"company_id": null` and **Sync** will do the clean up for you.

```json
[
  {
    "id": 6,
    "name": "Shawn Merrill",
    "company_id": 0
  }
]
```

## JSON Exporting

Sync provides an easy way to convert your NSManagedObject back into JSON. Just use the `export()` method.

``` objc
let user = //...
user.set(value: "John" for: "firstName")
user.set(value: "Sid" for: "lastName")

let userValues = user.export()
```

That's it, that's all you have to do, the keys will be magically transformed into a `snake_case` convention.

```json
{
  "first_name": "John",
  "last_name": "Sid"
}
```

### Excluding

If you don't want to export certain attribute or relationship, you can prohibit exporting by adding `sync.nonExportable` in the user info of the excluded attribute or relationship.

![non-exportable](https://raw.githubusercontent.com/3lvis/Sync/master/Images/pm-non-exportable.png)

### Relationships

It supports exporting relationships too.

```json
"first_name": "John",
"last_name": "Sid",
"notes": [
  {
    "id": 0,
    "text": "This is the text for the note A"
  },
  {
    "id": 1,
    "text": "This is the text for the note B"
  }
]
```

If you don't want relationships you can also ignore relationships:

```swift
let dictionary = user.export(using: .excludedRelationships)
```

```json
"first_name": "John",
"last_name": "Sid"
```

Or get them as nested attributes, something that Ruby on Rails uses (`accepts_nested_attributes_for`), for example for a user that has many notes:

```swift
var exportOptions = ExportOptions()
exportOptions.relationshipType = .nested
let dictionary = user.export(using: exportOptions)
```

```json
"first_name": "John",
"last_name": "Sid",
"notes_attributes": [
  {
    "0": {
      "id": 0,
      "text": "This is the text for the note A"
    },
    "1": {
      "id": 1,
      "text": "This is the text for the note B"
    }
  }
]
```

## FAQ

[Check our FAQ document.](https://github.com/3lvis/Sync/blob/master/docs/faq.md)

## Installation

### CocoaPods

```ruby
pod 'Sync', '~> 6'
```

### Carthage

```ruby
github "3lvis/Sync" ~> 6.0
```

### Supported iOS, OS X, watchOS and tvOS Versions

- iOS 8 or above
- OS X 10.10 or above
- watchOS 2.0 or above
- tvOS 9.0 or above

## Backers

Finding Sync helpful? Consider supporting further development and support by becoming a sponsor:
👉  https://github.com/sponsors/3lvis


## License

**Sync** is available under the MIT license. See the [LICENSE](https://github.com/3lvis/Sync/blob/master/LICENSE.md) file for more info.
