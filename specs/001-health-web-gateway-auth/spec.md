# Feature Specification: health-web Sign-In Through the Platform Gateway

**Feature Branch**: `001-health-web-gateway-auth`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "Deprecate and eliminate health-web's legacy ProcessManager Auth code
and move sign-in to the cluster's platform authentication gateway, using the architecture agreed in
the plan: the backend confirms sessions with the in-cluster gateway, identity is (issuer, subject),
and the browser keeps only a host-only session cookie."

## Background

`https://health.nacfson.cloud` is unusable today. The site loads for a moment, finds no session, and
sends the visitor to a sign-in address (`auth.nacfson.cloud/login`) that no longer exists. The visitor
ends on a bare "404 page not found" page. Even with a working sign-in page, the site would still
reject every request: it checks sessions with a sign-in service the cluster no longer runs.

The cluster's sign-in service (the platform gateway, backed by Google sign-in) is already set up to
accept health-web as a sign-in client. The missing part is health-web itself.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sign in and reach my data (Priority: P1)

A visitor opens `health.nacfson.cloud` without a session. They see the health sign-in screen, choose
to continue, complete Google sign-in on the platform's sign-in page, and land back in health-web on
the page they started from, with their own workout, diet, and weight data available.

**Why this priority**: Nothing in health-web works until this works. This story alone fixes the
outage.

**Independent Test**: In a fresh browser profile, open the site, sign in with a Google account, and
confirm the app loads and can save and re-read a weight entry.

**Acceptance Scenarios**:

1. **Given** a visitor with no session, **When** they open any health-web page, **Then** they see the
   health-web sign-in screen (not an error page), with one clear action to continue.
2. **Given** the visitor chooses to continue, **When** they complete Google sign-in, **Then** they
   return to health-web on the page they first requested, signed in.
3. **Given** a signed-in user, **When** they record a workout set, a meal, or a weight entry,
   **Then** it is saved and shown again after a page reload.
4. **Given** a visitor who signs in for the first time, **When** they land back in health-web,
   **Then** an empty personal account is ready for them without any extra registration step.
5. **Given** a visitor already signed in to another nacfson project, **When** they open health-web,
   **Then** they still pass through health-web's own sign-in handoff once, and are not asked for
   their Google credentials again while the platform session is valid.

---

### User Story 2 - Stay signed in, and leave cleanly (Priority: P2)

A signed-in user keeps using health-web across page reloads and new tabs without signing in again,
until their platform session ends. When they choose to sign out, they are signed out and their data
is no longer reachable from that browser.

**Why this priority**: Without it users either sign in on every reload or cannot end a session on a
shared device.

**Independent Test**: Sign in, reload, open a second tab, then sign out. Confirm that after sign-out a
reload shows the sign-in screen and no personal data is returned.

**Acceptance Scenarios**:

1. **Given** a signed-in user, **When** they reload the page or open the site in a new tab of the
   same browser, **Then** they remain signed in.
2. **Given** a signed-in user, **When** they choose sign-out in Settings, **Then** they see the
   sign-in screen, and any later data request from that browser is refused.
3. **Given** a user whose platform session has expired or been revoked elsewhere, **When** they next
   load or save data, **Then** they are shown the sign-in screen with a short "session ended"
   explanation instead of an error page or a silent failure.

---

### User Story 3 - Each person sees only their own data (Priority: P1)

Two different Google accounts use health-web. Each sees only the records they created. Nobody can
read or change another person's data by editing requests, adding headers, or reusing a session that
was issued for a different project.

**Why this priority**: Health and body data is personal. A sign-in fix that leaks data across
accounts is worse than the outage.

**Independent Test**: Sign in as account A and create a record. Sign in as account B in another
browser, confirm the record is absent, and confirm that requests carrying forged identity information
or another project's session are refused.

**Acceptance Scenarios**:

1. **Given** accounts A and B with their own records, **When** B lists, edits, or deletes records,
   **Then** only B's records are visible or affected.
2. **Given** a request that carries forged identity information (made-up user headers or tokens),
   **When** it reaches health-web, **Then** the forged information is ignored and the request is
   treated as unsigned-in.
3. **Given** a session issued for a different nacfson project, **When** it is presented to health-web,
   **Then** health-web refuses it.
4. **Given** the platform sign-in service is unreachable, **When** a user requests their data,
   **Then** health-web refuses the request with a "try again later" message and never serves data
   without a confirmed identity.

---

### User Story 4 - The old sign-in system is gone (Priority: P3)

The maintainer no longer finds any code path, configuration setting, user-facing text, or document
that refers to the retired ProcessManager sign-in. Operators no longer need to supply the retired
shared verification token.

**Why this priority**: Leftover code and docs already caused this outage once by pointing at a
service that no longer exists.

**Independent Test**: Search the repository for the retired names and endpoints. None remain outside
history records (changelogs and this spec). The service starts and works with no retired settings
present.

**Acceptance Scenarios**:

1. **Given** the finished change, **When** the repository is searched for the retired session cookie
   name, the retired verification endpoint, the retired token setting, and "ProcessManager SSO",
   **Then** matches appear only in historical changelogs and this feature's spec folder.
2. **Given** a deployment that provides none of the retired settings, **When** the service starts,
   **Then** it starts without warnings about missing sign-in configuration.

### Edge Cases

- The visitor abandons Google sign-in midway, or the handoff back to health-web arrives expired,
  replayed, or already used: they land on the health-web sign-in screen and can start again. No data
  is shown and no error page appears.
- A handoff back to health-web that was not started from the same browser (login forgery attempt) is
  refused.
- A "return to" target that points outside health-web is ignored. The user lands on the health-web
  home page instead.
- The platform renews the session while the user is active: the renewal is picked up without the
  user noticing.
- A save happens exactly as the session ends: the save is refused, the user is told the session
  ended, and nothing is silently lost (the form keeps its values until the user signs in again or
  leaves).
- Sign-out while the sign-in service is unreachable: health-web still ends its own session in that
  browser and tells the user the platform-wide sign-out could not be confirmed.
- The same Google account signs in from two browsers: both see the same data.
- The backend restarts during a sign-in handoff: the user is returned to the sign-in screen and can
  retry.

## Requirements *(mandatory)*

### Functional Requirements

**Sign-in**

- **FR-001**: Visitors without a confirmed session MUST see the health-web sign-in screen. They MUST
  NOT be sent to a retired or non-existent sign-in address.
- **FR-002**: Sign-in MUST be performed by the platform's shared sign-in service. health-web MUST NOT
  collect passwords or talk to Google directly.
- **FR-003**: After sign-in, the user MUST return to the health-web page they originally requested.
  Return targets MUST be limited to paths within health-web.
- **FR-004**: The sign-in handoff MUST be bound to the browser that started it, MUST be single-use,
  and MUST expire within minutes. Handoffs that fail these checks MUST be refused.
- **FR-005**: A first-time sign-in MUST create the user's health-web account automatically.

**Identity and data isolation**

- **FR-006**: A user MUST be identified only by the platform identity (issuing authority plus subject
  identifier). Email addresses MUST NOT be used to identify, look up, or link users.
- **FR-007**: health-web MUST accept only sessions issued for health-web and MUST refuse sessions
  issued for other projects.
- **FR-008**: Every read and write of personal data MUST be limited to the signed-in user's own
  records.
- **FR-009**: Identity information supplied by the browser or any client (headers, tokens, query
  values) MUST be ignored unless the platform sign-in service confirms it for this request.
- **FR-010**: If a session cannot be confirmed (rejected, expired, revoked, or the sign-in service is
  unreachable), personal data MUST NOT be served. Rejected sessions MUST be treated as signed out.
  An unreachable sign-in service MUST produce a "temporarily unavailable" response the app can show.

**Session lifetime**

- **FR-011**: A confirmed session MUST persist across reloads and tabs in the same browser until the
  platform ends it or the user signs out. Session lifetime limits are the platform's (currently
  about 1 hour idle and 8 hours maximum). health-web MUST NOT extend them.
- **FR-012**: The session credential held by the browser MUST NOT be readable by page scripts, MUST
  be sent only to health-web, and MUST be sent only over secure connections.
- **FR-013**: Data-changing requests MUST keep the existing cross-site request forgery protection.

**Sign-out**

- **FR-014**: Users MUST be able to sign out from Settings. Sign-out MUST end the session in
  health-web for that browser and MUST ask the platform to revoke the platform session.
- **FR-015**: After sign-out, later requests from that browser MUST be treated as unsigned-in.

**User-facing content**

- **FR-016**: The app MUST NOT show or rely on the user's email address. The account area in Settings
  MUST show the signed-in state and the sign-out action without an email.
- **FR-017**: Sign-in screen text MUST describe Google sign-in through nacfson. It MUST NOT mention
  the retired sign-in system or its cookie name.

**Removal of the retired system**

- **FR-018**: All code, configuration settings, tests, user-facing text, and current documentation
  for the retired ProcessManager sign-in MUST be removed. Historical changelogs MAY keep their
  records, marked as superseded.
- **FR-019**: The service MUST start and run with no shared sign-in secret configured.

**Operations**

- **FR-020**: The existing public, data-free startup check used by the deployment platform MUST keep
  working at the same address, so the deployment does not need to change its health checks.
- **FR-021**: Sign-in, sign-out, rejected-session, and sign-in-service-unavailable events MUST be
  logged with a reason. Session credentials and personal data MUST NOT be logged.

### Key Entities

- **Platform identity**: Who the person is according to the platform: issuing authority plus subject
  identifier. Assigned by the platform and stable across sign-ins.
- **health-web user account**: health-web's own record for a platform identity. Created on first
  sign-in, it owns all personal records (profile, workouts, meals, weights, templates, routines).
  Exactly one account per platform identity.
- **Browser session**: The signed-in state of one browser. It refers to a platform session, is
  renewed by the platform, and ends at sign-out, expiry, or revocation.
- **Sign-in handoff**: A short-lived, single-use, browser-bound step that carries the result of
  platform sign-in back to health-web.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first-time visitor goes from opening the site to seeing their (empty) dashboard in
  under 1 minute, excluding time spent on Google's own screens, with zero error pages.
- **SC-002**: 100% of visits without a session end on the health-web sign-in screen. None end on a
  "page not found" or other error page.
- **SC-003**: A signed-in user can reload or open new tabs at least 20 times within their session
  without being asked to sign in again.
- **SC-004**: In the isolation test (two accounts, forged identity information, another project's
  session, sign-in service down), 0 requests return another user's data or any data without a
  confirmed identity.
- **SC-005**: After sign-out, 100% of follow-up data requests from that browser are refused.
- **SC-006**: Searching the repository for the retired sign-in names and endpoints finds 0 matches
  outside historical changelogs and this spec folder.
- **SC-007**: Deploying the change requires no change to the deployment platform's health checks,
  routes, or network permissions. Only the released image version changes.

## Assumptions

- The platform side is already in place and is not changed by this feature: health-web is declared as
  a shared sign-in project, the sign-in service accepts health-web return addresses, a health-web
  sign-in audience exists, and health-web's backend may reach the sign-in service inside the cluster.
- No personal data exists in the current health-web database that must be carried over. Since
  deployment every data request has been refused for lack of a working sign-in, so no records could
  have been created. This is verified before release. If records are found, release stops and a data
  plan is added to this spec.
- Only Google sign-in through the platform is offered. Other sign-in methods are out of scope.
- The native mobile app keeps its own sign-in and is not affected.
- Business permissions stay as they are: every signed-in person may use health-web for their own
  data. There are no admin roles in health-web.
- Session duration, renewal, and revocation behave as defined by the platform's sign-in contract.
  health-web follows them.
- One backend instance serves health-web. Handoff state that lives only in memory is acceptable.
  Running several instances is out of scope.
