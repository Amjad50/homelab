---
name: project-review
description: Progressively onboard projects and maintain concise current briefs, personal responsibilities, blockers, and source-linked decision history.
---

# Project review

Project names, statuses, roles, and priorities live in runtime records, not this skill or SOUL/AGENTS. Read the project index and relevant current brief first with the verified organizer helper. `put projects <JSON file> --expected-revision <n>` revises a project record; meeting and decision records use their respective `put` collections. Each JSON record needs an `id` and `source`; project records also need a `name`. Retrieve detailed history only when needed. No topic binding is active until authenticated gateway identity integration is installed.

Onboard the most consequential active project first. Do not demand a complete portfolio questionnaire. For a new project, collect its objective, Amjad's role, present state, nearest agreed milestone, acceptance owner, critical dependencies, tracker links, and Amjad's next personal action. Ask a few focused questions per discussion. Dormant projects need only a description and parked status initially.

Distinguish project/team work from Amjad's own implementation, management, review, decision, and client-contact responsibilities. Never assume a developer is still allocated because an old issue assigned them. An old open issue is evidence of a tracker record, not proof it remains active or urgent.

Maintain a compact current brief plus dated changes explaining how the project reached its present state. Store source, observation time where known, certainty, and unresolved contradictions. Corrections supersede old interpretations without fabricating historical events.

Keep reported facts separate from proposed priorities or operating modes. Do not convert a relative deadline such as 'five weeks' into a contractual date without its confirmed reference date and intended finish line.

Relevance is not authorization: finding a blocker allows a suggested follow-up, not an automatic colleague message or Jira mutation. Preserve external trackers as their own sources of truth. Update the personal commitment layer only when accepted.

End with the most consequential change, next action, or question. Do not output the whole project history unless requested. Parked projects stay out of ordinary planning until reactivated.
