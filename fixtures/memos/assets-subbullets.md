# poc-demo-app-workspace-rules

- Select [+ New Workspace]

![scap-2026-10-22-160218](assets/scap-2026-10-22-160218.png)

- Fill in the name and owner like any other workspace.

![scap-2026-10-22-160246](assets/scap-2026-10-22-160246.png)

- Stop at Access Rules (AR)
  - Turn them on.
  - Define rule sets: inbound and outbound.

![scap-2026-10-22-160309](assets/scap-2026-10-22-160309.png)

- Example: allow port 8080 only.

![scap-2026-10-22-160322](assets/scap-2026-10-22-160322.png)

- Workspace creation finishing.

![scap-2026-10-22-160330](assets/scap-2026-10-22-160330.png)

- The workspace is ready now. Let’s check its overview.

![scap-2026-10-22-160337](assets/scap-2026-10-22-160337.png)

- Workspace overview
  - AR is **On**

![scap-2026-10-22-160403](assets/scap-2026-10-22-160403.png)

- Consider adding a test user to the new workspace.

![scap-2026-10-22-160421](assets/scap-2026-10-22-160421.png)

- Members can switch workspaces from the drop-down list.
  - Let’s select DEMO-TEAM.

![scap-2026-10-22-160446](assets/scap-2026-10-22-160446.png)

- Confirm the workspace details: name, owner and so on.

![scap-2026-10-22-160451](assets/scap-2026-10-22-160451.png)

- Check out **Settings** > **Network** > **Access Rules**
  - A default rule set is ready.

![scap-2026-10-22-160455](assets/scap-2026-10-22-160455.png)

- App creation starting.

![scap-2026-10-22-160529](assets/scap-2026-10-22-160529.png)

- Fill in the details for the app.
  - Scroll down to **Network**.

![scap-2026-10-22-160557](assets/scap-2026-10-22-160557.png)

- Since this is an AR-ready workspace
  - a rule set is required now.

![scap-2026-10-22-160616](assets/scap-2026-10-22-160616.png)

- Pick a rule set
  - The workspace comes with a default one, so it’s ready from day one.

![scap-2026-10-22-160626](assets/scap-2026-10-22-160626.png)

- App creation finishing.

![scap-2026-10-22-160647](assets/scap-2026-10-22-160647.png)

- From the app overview
  - the rule set is shown.

![scap-2026-10-22-160754](assets/scap-2026-10-22-160754.png)

- Moving to a plain workspace: SANDBOX
  - No default rule set is there.

![scap-2026-10-22-160830](assets/scap-2026-10-22-160830.png)

- Compared with a plain workspace
  - a rule set is optional.

![scap-2026-10-22-160909](assets/scap-2026-10-22-160909.png)

- As with any rule set, check its rules.
  - For example, some default rules are added.

![scap-2026-10-22-162008](assets/scap-2026-10-22-162008.png)

> See `poc-demo-app-access-rules` for how a rule set shapes traffic and so security.
