import Foundation

public struct DemoSeedData {
    public struct SeedProject: Sendable {
        public let id: String
        public let name: String
        public let status: String
        public let updatedAt: Date

        public init(id: String, name: String, status: String, updatedAt: Date) {
            self.id = id
            self.name = name
            self.status = status
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

    public struct SeedTag: Sendable {
        public let id: String
        public let name: String
        public let updatedAt: Date

        public init(id: String, name: String, updatedAt: Date) {
            self.id = id
            self.name = name
            self.updatedAt = updatedAt
        }
    }

    public struct SeedTask: Sendable {
        public let id: String
        public let projectID: String
        public let assigneeID: String?
        public let reviewerID: String?
        public let title: String
        public let descriptionText: String
        public let state: String
        public let tagIDs: [String]
        public let watcherIDs: [String]
        public let updatedAt: Date

        public init(
            id: String,
            projectID: String,
            assigneeID: String?,
            reviewerID: String? = nil,
            title: String,
            descriptionText: String,
            state: String,
            tagIDs: [String],
            watcherIDs: [String] = [],
            updatedAt: Date
        ) {
            self.id = id
            self.projectID = projectID
            self.assigneeID = assigneeID
            self.reviewerID = reviewerID
            self.title = title
            self.descriptionText = descriptionText
            self.state = state
            self.tagIDs = tagIDs
            self.watcherIDs = watcherIDs
            self.updatedAt = updatedAt
        }
    }

    public struct SeedComment: Sendable {
        public let id: String
        public let taskID: String
        public let authorUserID: String
        public let body: String
        public let createdAt: Date

        public init(id: String, taskID: String, authorUserID: String, body: String, createdAt: Date) {
            self.id = id
            self.taskID = taskID
            self.authorUserID = authorUserID
            self.body = body
            self.createdAt = createdAt
        }
    }

    public let projects: [SeedProject]
    public let users: [SeedUser]
    public let tags: [SeedTag]
    public let tasks: [SeedTask]
    public let comments: [SeedComment]

    public init(
        projects: [SeedProject],
        users: [SeedUser],
        tags: [SeedTag],
        tasks: [SeedTask],
        comments: [SeedComment]
    ) {
        self.projects = projects
        self.users = users
        self.tags = tags
        self.tasks = tasks
        self.comments = comments
    }

    public static func generate() -> DemoSeedData {
        let baseDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z
        func at(_ minutes: Int) -> Date {
            baseDate.addingTimeInterval(TimeInterval(minutes * 60))
        }

        let projects: [SeedProject] = [
            .init(id: "project-1", name: "Account Security Controls", status: "On track", updatedAt: at(540)),
            .init(id: "project-2", name: "Team Notifications Reliability", status: "At risk", updatedAt: at(525)),
            .init(id: "project-3", name: "Support Inbox Refresh", status: "On track", updatedAt: at(510))
        ]

        let users: [SeedUser] = [
            .init(id: "user-1", displayName: "Ava Martinez", role: "iOS Engineer", updatedAt: at(60)),
            .init(id: "user-2", displayName: "Noah Kim", role: "Backend Engineer", updatedAt: at(70)),
            .init(id: "user-3", displayName: "Mia Patel", role: "Product Designer", updatedAt: at(80)),
            .init(id: "user-4", displayName: "Liam Brown", role: "Product Manager", updatedAt: at(90)),
            .init(id: "user-5", displayName: "Sofia Garcia", role: "QA Engineer", updatedAt: at(100)),
            .init(id: "user-6", displayName: "Ethan Lee", role: "DevOps Engineer", updatedAt: at(110))
        ]

        let tags: [SeedTag] = [
            .init(id: "tag-1", name: "ios", updatedAt: at(120)),
            .init(id: "tag-2", name: "backend", updatedAt: at(121)),
            .init(id: "tag-3", name: "api", updatedAt: at(122)),
            .init(id: "tag-4", name: "sync", updatedAt: at(123)),
            .init(id: "tag-5", name: "security", updatedAt: at(124)),
            .init(id: "tag-6", name: "ux", updatedAt: at(125)),
            .init(id: "tag-7", name: "qa", updatedAt: at(126)),
            .init(id: "tag-8", name: "release", updatedAt: at(127)),
            .init(id: "tag-9", name: "notifications", updatedAt: at(128)),
            .init(id: "tag-10", name: "reliability", updatedAt: at(129)),
            .init(id: "tag-11", name: "support", updatedAt: at(130)),
            .init(id: "tag-12", name: "analytics", updatedAt: at(131))
        ]

        let tasks: [SeedTask] = [
            .init(
                id: "task-1",
                projectID: "project-1",
                assigneeID: "user-1",
                reviewerID: "user-4",
                title: "Add session timeout controls to account settings",
                descriptionText: """
                Build the mobile settings UI for session timeout and forced re-authentication controls.

                This is the primary demo task for account-security work and is intentionally rich: it has an assignee, multiple tags, and active comments.
                """,
                state: "inProgress",
                tagIDs: ["tag-1", "tag-5", "tag-6"],
                watcherIDs: ["user-2", "user-5"],
                updatedAt: at(300)
            ),
            .init(
                id: "task-2",
                projectID: "project-1",
                assigneeID: "user-2",
                reviewerID: "user-1",
                title: "Validate security policy PATCH payload on backend",
                descriptionText: """
                Enforce allowed values for timeout minutes and re-auth policy. Reject unknown keys so mobile payloads stay explicit.
                """,
                state: "todo",
                tagIDs: ["tag-2", "tag-3", "tag-5"],
                watcherIDs: ["user-4"],
                updatedAt: at(305)
            ),
            .init(
                id: "task-3",
                projectID: "project-1",
                assigneeID: "user-5",
                reviewerID: "user-4",
                title: "Write QA checklist for forced re-auth scenarios",
                descriptionText: """
                Cover app relaunch, expired session recovery, and offline-to-online transitions after the policy changes.
                """,
                state: "todo",
                tagIDs: ["tag-5", "tag-7", "tag-8"],
                watcherIDs: ["user-1", "user-3"],
                updatedAt: at(310)
            ),
            .init(
                id: "task-4",
                projectID: "project-1",
                assigneeID: "user-3",
                reviewerID: "user-1",
                title: "Polish warning copy and hierarchy in security settings",
                descriptionText: """
                Refine the warning copy and screen hierarchy so risky actions are clear without blocking the flow.
                """,
                state: "done",
                tagIDs: ["tag-1", "tag-6"],
                watcherIDs: ["user-4"],
                updatedAt: at(315)
            ),
            .init(
                id: "task-5",
                projectID: "project-1",
                assigneeID: "user-6",
                reviewerID: "user-2",
                title: "Enable rollout flag for account security controls",
                descriptionText: """
                Prepare release gating so the feature can be enabled per environment after QA sign-off.
                """,
                state: "inProgress",
                tagIDs: ["tag-2", "tag-8", "tag-10"],
                watcherIDs: ["user-4", "user-5"],
                updatedAt: at(320)
            ),
            .init(
                id: "task-6",
                projectID: "project-2",
                assigneeID: "user-1",
                reviewerID: "user-2",
                title: "Fix duplicate push preference sync after reconnect",
                descriptionText: """
                The preferences screen can duplicate local rows after reconnect. Backend remains correct; the client refresh path needs better scoped sync.
                """,
                state: "inProgress",
                tagIDs: ["tag-1", "tag-4", "tag-9", "tag-10"],
                watcherIDs: ["user-4", "user-6"],
                updatedAt: at(330)
            ),
            .init(
                id: "task-7",
                projectID: "project-2",
                assigneeID: "user-2",
                reviewerID: "user-6",
                title: "Add idempotency guard to notification preference writes",
                descriptionText: """
                Prevent duplicate writes when the same save is retried. Keep the response payload stable for targeted refresh.
                """,
                state: "todo",
                tagIDs: ["tag-2", "tag-3", "tag-9", "tag-10"],
                watcherIDs: ["user-1", "user-4"],
                updatedAt: at(335)
            ),
            .init(
                id: "task-8",
                projectID: "project-2",
                assigneeID: "user-5",
                reviewerID: "user-2",
                title: "Verify scoped delete behavior for removed notification channels",
                descriptionText: """
                Confirm channel lists only delete rows inside the synced parent scope and never remove channels from other users/projects.
                """,
                state: "todo",
                tagIDs: ["tag-4", "tag-7", "tag-9"],
                watcherIDs: ["user-4"],
                updatedAt: at(340)
            ),
            .init(
                id: "task-9",
                projectID: "project-2",
                assigneeID: nil,
                reviewerID: "user-4",
                title: "Draft incident playbook for notification delivery degradation",
                descriptionText: """
                Capture triage steps, rollback criteria, and communication templates. This task starts unassigned to demonstrate null assignee handling.
                """,
                state: "todo",
                tagIDs: ["tag-8", "tag-9", "tag-10"],
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
                tagIDs: ["tag-1", "tag-6", "tag-11"],
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
                tagIDs: ["tag-2", "tag-3", "tag-4", "tag-11", "tag-12"],
                updatedAt: at(355)
            ),
            .init(
                id: "task-12",
                projectID: "project-3",
                assigneeID: "user-5",
                title: "Backfill regression checks for comment composer failures",
                descriptionText: """
                Add regression coverage for failed sends, retry UI, and list refresh after comment deletion.
                """,
                state: "inProgress",
                tagIDs: ["tag-7", "tag-10", "tag-11"],
                updatedAt: at(360)
            )
        ]

        let comments: [SeedComment] = [
            .init(id: "comment-1", taskID: "task-1", authorUserID: "user-4", body: "Keep the first version focused on timeout + re-auth toggle. We can defer device management.", createdAt: at(301)),
            .init(id: "comment-2", taskID: "task-1", authorUserID: "user-1", body: "I have the settings screen layout in place. Next step is wiring the save action to the backend patch.", createdAt: at(302)),
            .init(id: "comment-3", taskID: "task-2", authorUserID: "user-2", body: "I’ll reject unknown keys so mobile catches contract drift quickly during development.", createdAt: at(306)),
            .init(id: "comment-4", taskID: "task-2", authorUserID: "user-4", body: "Perfect. That will make payload mistakes obvious while we iterate on the UI.", createdAt: at(307)),
            .init(id: "comment-5", taskID: "task-3", authorUserID: "user-5", body: "I want explicit coverage for offline relaunch after policy change, even if offline replay ships later.", createdAt: at(311)),
            .init(id: "comment-6", taskID: "task-3", authorUserID: "user-6", body: "I can help test the environment flag path once QA cases are written.", createdAt: at(312)),
            .init(id: "comment-7", taskID: "task-4", authorUserID: "user-3", body: "Updated copy reduces alarm wording while keeping the security implication clear.", createdAt: at(316)),
            .init(id: "comment-8", taskID: "task-5", authorUserID: "user-6", body: "Rollout flag is ready in staging. Waiting for QA sign-off before enabling it there.", createdAt: at(321)),
            .init(id: "comment-9", taskID: "task-5", authorUserID: "user-5", body: "I’ll mark sign-off after I finish the forced re-auth checklist and a regression pass.", createdAt: at(322)),
            .init(id: "comment-10", taskID: "task-6", authorUserID: "user-1", body: "The duplicate row issue happens after reconnect + refresh. Scoped sync should fix this cleanly.", createdAt: at(331)),
            .init(id: "comment-11", taskID: "task-6", authorUserID: "user-2", body: "Backend payload is already authoritative. If mobile re-syncs the project slice, duplicates should disappear.", createdAt: at(332)),
            .init(id: "comment-12", taskID: "task-7", authorUserID: "user-2", body: "I’m adding an idempotency token internally but keeping the response shape unchanged for the demo.", createdAt: at(336)),
            .init(id: "comment-13", taskID: "task-8", authorUserID: "user-5", body: "I’ll verify deletes stay scoped to the parent list. That is the main regression risk here.", createdAt: at(341)),
            .init(id: "comment-14", taskID: "task-9", authorUserID: "user-4", body: "Leaving this unassigned for now is intentional. It helps us test null assignee flows in the demo.", createdAt: at(346)),
            .init(id: "comment-15", taskID: "task-10", authorUserID: "user-3", body: "I’ll keep the chip subtle so the row still scans well on smaller devices.", createdAt: at(351)),
            .init(id: "comment-16", taskID: "task-10", authorUserID: "user-1", body: "Once the chip lands, I’ll verify the task list refreshes correctly when assignee changes.", createdAt: at(352)),
            .init(id: "comment-17", taskID: "task-11", authorUserID: "user-2", body: "This is the payload contract cleanup task. It should reduce custom mapping in both clients.", createdAt: at(356)),
            .init(id: "comment-18", taskID: "task-11", authorUserID: "user-4", body: "Great. Consistent keys make the API docs much easier to maintain and review.", createdAt: at(357)),
            .init(id: "comment-19", taskID: "task-12", authorUserID: "user-5", body: "I added cases for failed sends and comment delete refresh. Need one more pass on retry UX.", createdAt: at(361)),
            .init(id: "comment-20", taskID: "task-12", authorUserID: "user-1", body: "Please include a case where the comment list re-syncs after delete so we catch stale UI rows.", createdAt: at(362))
        ]

        return DemoSeedData(
            projects: projects,
            users: users,
            tags: tags,
            tasks: tasks,
            comments: comments
        )
    }
}
