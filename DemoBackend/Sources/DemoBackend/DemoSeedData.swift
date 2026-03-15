import Foundation

public struct DemoSeedData {
    public struct SeedProject: Sendable {
        public let id: String
        public let name: String
        public let createdAt: Date
        public let updatedAt: Date

        public init(id: String, name: String, createdAt: Date, updatedAt: Date) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    public struct SeedUser: Sendable {
        public let id: String
        public let displayName: String
        public let createdAt: Date
        public let updatedAt: Date

        public init(id: String, displayName: String, createdAt: Date, updatedAt: Date) {
            self.id = id
            self.displayName = displayName
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    public struct SeedTask: Sendable {
        public let id: String
        public let projectID: String
        public let assigneeID: String?
        public let reviewerIDs: [String]
        public let authorID: String
        public let title: String
        public let descriptionText: String?
        public let state: String
        public let watcherIDs: [String]
        public let createdAt: Date
        public let updatedAt: Date

        public init(
            id: String,
            projectID: String,
            assigneeID: String?,
            reviewerIDs: [String] = [],
            authorID: String? = nil,
            title: String,
            descriptionText: String?,
            state: String,
            watcherIDs: [String] = [],
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.projectID = projectID
            self.assigneeID = assigneeID
            self.reviewerIDs = reviewerIDs
            self.authorID = authorID ?? assigneeID ?? reviewerIDs.first ?? id
            self.title = title
            self.descriptionText = descriptionText
            self.state = state
            self.watcherIDs = watcherIDs
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    public struct SeedItem: Sendable {
        public let id: String
        public let taskID: String
        public let title: String
        public let position: Int
        public let createdAt: Date
        public let updatedAt: Date

        public init(
            id: String,
            taskID: String,
            title: String,
            position: Int,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.taskID = taskID
            self.title = title
            self.position = position
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    public let projects: [SeedProject]
    public let users: [SeedUser]
    public let tasks: [SeedTask]
    public let items: [SeedItem]

    public init(
        projects: [SeedProject],
        users: [SeedUser],
        tasks: [SeedTask],
        items: [SeedItem] = []
    ) {
        self.projects = projects
        self.users = users
        self.tasks = tasks
        self.items = items
    }

    // Stable UUID constants for the canonical seed dataset.
    // These are fixed — not random — so the demo loads consistent data across fresh installs.
    public enum SeedIDs {
        public enum Projects {
            public static let accountSecurity          = "C3E7A1B2-1001-0000-0000-000000000001"
            public static let notificationsReliability = "C3E7A1B2-1001-0000-0000-000000000002"
            public static let supportInbox             = "C3E7A1B2-1001-0000-0000-000000000003"
        }
        public enum Users {
            public static let avaMartinez = "C3E7A1B2-2001-0000-0000-000000000001"
            public static let noahKim     = "C3E7A1B2-2001-0000-0000-000000000002"
            public static let miaPatel    = "C3E7A1B2-2001-0000-0000-000000000003"
            public static let liamBrown   = "C3E7A1B2-2001-0000-0000-000000000004"
            public static let sofiaGarcia = "C3E7A1B2-2001-0000-0000-000000000005"
            public static let ethanLee    = "C3E7A1B2-2001-0000-0000-000000000006"
        }
        public enum Tasks {
            public static let sessionTimeout      = "C3E7A1B2-3001-0000-0000-000000000001"
            public static let securityPolicyPatch = "C3E7A1B2-3001-0000-0000-000000000002"
            public static let qaItemList          = "C3E7A1B2-3001-0000-0000-000000000003"
            public static let warningCopy         = "C3E7A1B2-3001-0000-0000-000000000004"
            public static let rolloutFlag         = "C3E7A1B2-3001-0000-0000-000000000005"
            public static let duplicatePushFix    = "C3E7A1B2-3001-0000-0000-000000000006"
            public static let idempotencyGuard    = "C3E7A1B2-3001-0000-0000-000000000007"
            public static let scopedDeleteVerify  = "C3E7A1B2-3001-0000-0000-000000000008"
            public static let incidentPlaybook    = "C3E7A1B2-3001-0000-0000-000000000009"
            public static let assigneeChip        = "C3E7A1B2-3001-0000-0000-000000000010"
            public static let inboxFilterKeys     = "C3E7A1B2-3001-0000-0000-000000000011"
            public static let regressionChecks    = "C3E7A1B2-3001-0000-0000-000000000012"
        }
        public enum Items {
            public static let sessionRequirements = "C3E7A1B2-4001-0000-0000-000000000001"
            public static let sessionDraftPlan    = "C3E7A1B2-4001-0000-0000-000000000002"
            public static let qaLaunchFlow        = "C3E7A1B2-4001-0000-0000-000000000003"
            public static let qaOfflineRecovery   = "C3E7A1B2-4001-0000-0000-000000000004"
            public static let pushReproCase       = "C3E7A1B2-4001-0000-0000-000000000005"
            public static let pushVerifyFix       = "C3E7A1B2-4001-0000-0000-000000000006"
        }
    }

    public static func generate() -> DemoSeedData {
        let baseDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z
        func at(_ minutes: Int) -> Date {
            baseDate.addingTimeInterval(TimeInterval(minutes * 60))
        }

        let p = SeedIDs.Projects.self
        let u = SeedIDs.Users.self
        let t = SeedIDs.Tasks.self
        let c = SeedIDs.Items.self

        let projects: [SeedProject] = [
            .init(id: p.accountSecurity,          name: "Account Security Controls",      createdAt: at(540), updatedAt: at(540)),
            .init(id: p.notificationsReliability,  name: "Team Notifications Reliability", createdAt: at(525), updatedAt: at(525)),
            .init(id: p.supportInbox,              name: "Support Inbox Refresh",           createdAt: at(510), updatedAt: at(510))
        ]

        let users: [SeedUser] = [
            .init(id: u.avaMartinez, displayName: "Ava Martinez", createdAt: at(60),  updatedAt: at(60)),
            .init(id: u.noahKim,     displayName: "Noah Kim", createdAt: at(70),  updatedAt: at(70)),
            .init(id: u.miaPatel,    displayName: "Mia Patel", createdAt: at(80),  updatedAt: at(80)),
            .init(id: u.liamBrown,   displayName: "Liam Brown", createdAt: at(90),  updatedAt: at(90)),
            .init(id: u.sofiaGarcia, displayName: "Sofia Garcia", createdAt: at(100), updatedAt: at(100)),
            .init(id: u.ethanLee,    displayName: "Ethan Lee", createdAt: at(110), updatedAt: at(110))
        ]

        let tasks: [SeedTask] = [
            .init(
                id: t.sessionTimeout,
                projectID: p.accountSecurity,
                assigneeID: u.avaMartinez,
                reviewerIDs: [u.liamBrown],
                authorID: u.liamBrown,
                title: "Add session timeout controls to account settings",
                descriptionText: "Keep session controls clear and safe for account-security settings.",
                state: "inProgress",
                watcherIDs: [u.noahKim, u.sofiaGarcia],
                createdAt: at(300), updatedAt: at(300)
            ),
            .init(
                id: t.securityPolicyPatch,
                projectID: p.accountSecurity,
                assigneeID: u.noahKim,
                reviewerIDs: [u.avaMartinez],
                authorID: u.liamBrown,
                title: "Validate security policy PATCH payload",
                descriptionText: "Protect the API contract for security settings updates.",
                state: "todo",
                watcherIDs: [u.liamBrown],
                createdAt: at(305), updatedAt: at(305)
            ),
            .init(
                id: t.qaItemList,
                projectID: p.accountSecurity,
                assigneeID: u.sofiaGarcia,
                reviewerIDs: [u.liamBrown],
                authorID: u.miaPatel,
                title: "Write QA item list for forced re-auth scenarios",
                descriptionText: "Catch risky session recovery regressions before rollout.",
                state: "todo",
                watcherIDs: [u.avaMartinez, u.miaPatel],
                createdAt: at(310), updatedAt: at(310)
            ),
            .init(
                id: t.warningCopy,
                projectID: p.accountSecurity,
                assigneeID: u.miaPatel,
                reviewerIDs: [u.avaMartinez],
                authorID: u.liamBrown,
                title: "Polish warning copy and hierarchy in security settings",
                descriptionText: "Make risky security actions easier to understand at a glance.",
                state: "done",
                watcherIDs: [u.liamBrown],
                createdAt: at(315), updatedAt: at(315)
            ),
            .init(
                id: t.rolloutFlag,
                projectID: p.accountSecurity,
                assigneeID: u.ethanLee,
                reviewerIDs: [u.noahKim],
                authorID: u.avaMartinez,
                title: "Enable rollout flag for account security controls",
                descriptionText: "Enable a controlled rollout after QA approval.",
                state: "inProgress",
                watcherIDs: [u.liamBrown, u.sofiaGarcia],
                createdAt: at(320), updatedAt: at(320)
            ),
            .init(
                id: t.duplicatePushFix,
                projectID: p.notificationsReliability,
                assigneeID: u.avaMartinez,
                reviewerIDs: [u.noahKim],
                authorID: u.liamBrown,
                title: "Fix duplicate push preference sync",
                descriptionText: "Stop duplicate rows from eroding trust after reconnect.",
                state: "inProgress",
                watcherIDs: [u.liamBrown, u.ethanLee],
                createdAt: at(330), updatedAt: at(330)
            ),
            .init(
                id: t.idempotencyGuard,
                projectID: p.notificationsReliability,
                assigneeID: u.noahKim,
                reviewerIDs: [u.ethanLee],
                authorID: u.avaMartinez,
                title: "Prevent duplicate notification preference writes",
                descriptionText: "Make repeated saves safe and predictable.",
                state: "todo",
                watcherIDs: [u.avaMartinez, u.liamBrown],
                createdAt: at(335), updatedAt: at(335)
            ),
            .init(
                id: t.scopedDeleteVerify,
                projectID: p.notificationsReliability,
                assigneeID: u.sofiaGarcia,
                reviewerIDs: [u.noahKim],
                authorID: u.ethanLee,
                title: "Verify scoped notification channel deletes",
                descriptionText: "Prevent scoped deletes from removing the wrong channels.",
                state: "todo",
                watcherIDs: [u.liamBrown],
                createdAt: at(340), updatedAt: at(340)
            ),
            .init(
                id: t.incidentPlaybook,
                projectID: p.notificationsReliability,
                assigneeID: nil,
                reviewerIDs: [u.liamBrown],
                authorID: u.miaPatel,
                title: "Draft incident playbook for notification delivery degradation",
                descriptionText: "Speed up response during notification delivery incidents.",
                state: "todo",
                watcherIDs: [u.noahKim, u.ethanLee],
                createdAt: at(345), updatedAt: at(345)
            ),
            .init(
                id: t.assigneeChip,
                projectID: p.supportInbox,
                assigneeID: u.miaPatel,
                authorID: u.liamBrown,
                title: "Add assignee chip to support rows",
                descriptionText: "Help support agents see ownership without opening each thread.",
                state: "inProgress",
                createdAt: at(350), updatedAt: at(350)
            ),
            .init(
                id: t.inboxFilterKeys,
                projectID: p.supportInbox,
                assigneeID: u.noahKim,
                authorID: u.avaMartinez,
                title: "Normalize inbox filter payload keys across clients",
                descriptionText: "Keep filters consistent across clients and backend services.",
                state: "done",
                createdAt: at(355), updatedAt: at(355)
            ),
            .init(
                id: t.regressionChecks,
                projectID: p.supportInbox,
                assigneeID: u.sofiaGarcia,
                authorID: u.miaPatel,
                title: "Backfill regression checks for task detail edits",
                descriptionText: "Reduce regressions in task editing flows.",
                state: "inProgress",
                createdAt: at(360), updatedAt: at(360)
            )
        ]

        let items: [SeedItem] = [
            .init(
                id: c.sessionRequirements,
                taskID: t.sessionTimeout,
                title: "Gather requirements",
                position: 0,
                createdAt: at(301),
                updatedAt: at(301)
            ),
            .init(
                id: c.sessionDraftPlan,
                taskID: t.sessionTimeout,
                title: "Draft implementation plan",
                position: 1,
                createdAt: at(302),
                updatedAt: at(302)
            ),
            .init(
                id: c.qaLaunchFlow,
                taskID: t.qaItemList,
                title: "Relauch flow after timeout",
                position: 0,
                createdAt: at(311),
                updatedAt: at(311)
            ),
            .init(
                id: c.qaOfflineRecovery,
                taskID: t.qaItemList,
                title: "Offline to online recovery",
                position: 1,
                createdAt: at(312),
                updatedAt: at(312)
            ),
            .init(
                id: c.pushReproCase,
                taskID: t.duplicatePushFix,
                title: "Capture repro case",
                position: 0,
                createdAt: at(331),
                updatedAt: at(331)
            ),
            .init(
                id: c.pushVerifyFix,
                taskID: t.duplicatePushFix,
                title: "Verify fix after reconnect",
                position: 1,
                createdAt: at(332),
                updatedAt: at(332)
            )
        ]

        return DemoSeedData(
            projects: projects,
            users: users,
            tasks: tasks,
            items: items
        )
    }
}
