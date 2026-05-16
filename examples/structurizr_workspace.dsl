workspace "Project Tracker" "Internal project-management workspace" {

    model {
        qa  = person "QA Engineer"  "Reviews tasks and approves milestones"
        dev = person "Developer"    "Submits patches"

        rm = softwareSystem "Project Tracker" "Web + CLI for tracking tasks and project status" {
            web    = container "Web App"          "JavaScript SPA"        "React"
            api    = container "API"              "REST + business logic" "FastAPI"
            db     = container "Database"         "Stores triage state"   "PostgreSQL" "Database"
            poller = container "Data Poller"      "Polls CI results"      "Python worker"
        }

        ci     = softwareSystem "CI Platform" "Test orchestration & runner"  "External"
        jira   = softwareSystem "Tracker"     "Tickets and work items"       "External"
        slack  = softwareSystem "Slack"       "Notifications"                "External"

        qa  -> web    "Triages via"
        dev -> web    "Submits patches via"
        web -> api    "Calls" "JSON / HTTPS"
        api -> db     "Reads / writes"
        api -> jira   "Pulls ticket status"
        poller -> ci   "Polls"        "REST"
        poller -> db   "Stores results"
        api -> slack  "Posts updates"   "Webhook"
    }

    views {
        systemContext rm "ProjectTracker_Context" {
            include *
            autolayout lr
        }
        container rm "ProjectTracker_Container" {
            include *
            autolayout tb
        }
        styles {
            element "Person" {
                background "#08427b"
                color "#ffffff"
                shape Person
            }
            element "External" {
                background "#999999"
                color "#ffffff"
            }
            element "Database" {
                shape Cylinder
            }
        }
    }
}
