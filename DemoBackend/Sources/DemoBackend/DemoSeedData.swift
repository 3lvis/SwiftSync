import Foundation

public struct DemoSeedData {
    public struct SeedProject: Sendable {
        public let id: String
        public let name: String
        public let updatedAt: Date

        public init(id: String, name: String, updatedAt: Date) {
            self.id = id
            self.name = name
            self.updatedAt = updatedAt
        }
    }

    public struct SeedUser: Sendable {
        public let id: String
        public let displayName: String
        public let role: String
        public let updatedAt: Date

        public init(id: String, displayName: String, role: String, updatedAt: Date) {
            self.id = id
            self.displayName = displayName
            self.role = role
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
        public let descriptionText: String
        public let state: String
        public let watcherIDs: [String]
        public let updatedAt: Date

        public init(
            id: String,
            projectID: String,
            assigneeID: String?,
            reviewerIDs: [String] = [],
            authorID: String? = nil,
            title: String,
            descriptionText: String,
            state: String,
            watcherIDs: [String] = [],
            updatedAt: Date
        ) {
            self.id = id
            self.projectID = projectID
            self.assigneeID = assigneeID
            self.reviewerIDs = reviewerIDs
            self.authorID = authorID ?? assigneeID ?? reviewerIDs.first ?? "user-1"
            self.title = title
            self.descriptionText = descriptionText
            self.state = state
            self.watcherIDs = watcherIDs
            self.updatedAt = updatedAt
        }
    }

    public let projects: [SeedProject]
    public let users: [SeedUser]
    public let tasks: [SeedTask]

    public init(
        projects: [SeedProject],
        users: [SeedUser],
        tasks: [SeedTask]
    ) {
        self.projects = projects
        self.users = users
        self.tasks = tasks
    }

    public static func generate() -> DemoSeedData {
        let baseDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z
        func at(_ minutes: Int) -> Date {
            baseDate.addingTimeInterval(TimeInterval(minutes * 60))
        }

        let projects: [SeedProject] = [
            .init(id: "project-1", name: "Account Security Controls", updatedAt: at(540)),
            .init(id: "project-2", name: "Team Notifications Reliability", updatedAt: at(525)),
            .init(id: "project-3", name: "Support Inbox Refresh", updatedAt: at(510))
        ]

        let users: [SeedUser] = [
            .init(id: "user-1", displayName: "Ava Martinez", role: "iOS Engineer", updatedAt: at(60)),
            .init(id: "user-2", displayName: "Noah Kim", role: "Backend Engineer", updatedAt: at(70)),
            .init(id: "user-3", displayName: "Mia Patel", role: "Product Designer", updatedAt: at(80)),
            .init(id: "user-4", displayName: "Liam Brown", role: "Product Manager", updatedAt: at(90)),
            .init(id: "user-5", displayName: "Sofia Garcia", role: "QA Engineer", updatedAt: at(100)),
            .init(id: "user-6", displayName: "Ethan Lee", role: "DevOps Engineer", updatedAt: at(110))
        ]

        let tasks: [SeedTask] = [
            .init(
                id: "task-1",
                projectID: "project-1",
                assigneeID: "user-1",
                reviewerIDs: ["user-4"],
                title: "Add session timeout controls to account settings",
                descriptionText: """
                Build the mobile settings UI for session timeout and forced re-authentication controls.

                This is the primary demo task for account-security work and is intentionally rich: it has an assignee.
                """,
                state: "inProgress",
                watcherIDs: ["user-2", "user-5"],
                updatedAt: at(300)
            ),
            .init(
                id: "task-2",
                projectID: "project-1",
                assigneeID: "user-2",
                reviewerIDs: ["user-1"],
                title: "Validate security policy PATCH payload on backend",
                descriptionText: """
                Enforce allowed values for timeout minutes and re-auth policy. Reject unknown keys so mobile payloads stay explicit.
                """,
                state: "todo",
                watcherIDs: ["user-4"],
                updatedAt: at(305)
            ),
            .init(
                id: "task-3",
                projectID: "project-1",
                assigneeID: "user-5",
                reviewerIDs: ["user-4"],
                title: "Write QA checklist for forced re-auth scenarios",
                descriptionText: """
                Cover app relaunch, expired session recovery, and offline-to-online transitions after the policy changes.
                """,
                state: "todo",
                watcherIDs: ["user-1", "user-3"],
                updatedAt: at(310)
            ),
            .init(
                id: "task-4",
                projectID: "project-1",
                assigneeID: "user-3",
                reviewerIDs: ["user-1"],
                title: "Polish warning copy and hierarchy in security settings",
                descriptionText: """
                Refine the warning copy and screen hierarchy so risky actions are clear without blocking the flow.
                """,
                state: "done",
                watcherIDs: ["user-4"],
                updatedAt: at(315)
            ),
            .init(
                id: "task-5",
                projectID: "project-1",
                assigneeID: "user-6",
                reviewerIDs: ["user-2"],
                title: "Enable rollout flag for account security controls",
                descriptionText: """
                Prepare release gating so the feature can be enabled per environment after QA sign-off.
                """,
                state: "inProgress",
                watcherIDs: ["user-4", "user-5"],
                updatedAt: at(320)
            ),
            .init(
                id: "task-6",
                projectID: "project-2",
                assigneeID: "user-1",
                reviewerIDs: ["user-2"],
                title: "Fix duplicate push preference sync after reconnect",
                descriptionText: """
                The preferences screen can duplicate local rows after reconnect. Backend remains correct; the client refresh path needs better scoped sync.
                """,
                state: "inProgress",
                watcherIDs: ["user-4", "user-6"],
                updatedAt: at(330)
            ),
            .init(
                id: "task-7",
                projectID: "project-2",
                assigneeID: "user-2",
                reviewerIDs: ["user-6"],
                title: "Add idempotency guard to notification preference writes",
                descriptionText: """
                Prevent duplicate writes when the same save is retried. Keep the response payload stable for targeted refresh.
                """,
                state: "todo",
                watcherIDs: ["user-1", "user-4"],
                updatedAt: at(335)
            ),
            .init(
                id: "task-8",
                projectID: "project-2",
                assigneeID: "user-5",
                reviewerIDs: ["user-2"],
                title: "Verify scoped delete behavior for removed notification channels",
                descriptionText: """
                Confirm channel lists only delete rows inside the synced parent scope and never remove channels from other users/projects.
                """,
                state: "todo",
                watcherIDs: ["user-4"],
                updatedAt: at(340)
            ),
            .init(
                id: "task-9",
                projectID: "project-2",
                assigneeID: nil,
                reviewerIDs: ["user-4"],
                title: "Draft incident playbook for notification delivery degradation",
                descriptionText: """
                Capture triage steps, rollback criteria, and communication templates. This task starts unassigned to demonstrate null assignee handling.
                """,
                state: "todo",
                watcherIDs: ["user-2", "user-6"],
                updatedAt: at(345)
            ),
            .init(
                id: "task-10",
                projectID: "project-3",
                assigneeID: "user-3",
                title: "Add assignee chip to support conversation rows",
                descriptionText: """
                Show assigned owner directly in the inbox list to reduce context switching for support agents.
                """,
                state: "inProgress",
                updatedAt: at(350)
            ),
            .init(
                id: "task-11",
                projectID: "project-3",
                assigneeID: "user-2",
                title: "Normalize inbox filter payload keys across clients",
                descriptionText: """
                Align filter key naming across iOS and backend so imports/exports and analytics events use the same contract.
                """,
                state: "done",
                updatedAt: at(355)
            ),
            .init(
                id: "task-12",
                projectID: "project-3",
                assigneeID: "user-5",
                title: "Backfill regression checks for task detail edits",
                descriptionText: """
                Add regression coverage for failed saves, retry UI, and list refresh after task edits.
                """,
                state: "inProgress",
                updatedAt: at(360)
            )
        ]

        return DemoSeedData(
            projects: projects,
            users: users,
            tasks: tasks
        )
    }
}
