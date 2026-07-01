# CareOrbit Project Specification

Last updated: 2026-05-19

## 1. Project Overview

CareOrbit is a healthcare ERP, EMR, and AI-ready web application for clinics and hospitals. The current implementation provides a branded public website, email/password authentication, a protected application shell, dashboard metrics, patient record creation/listing, and appointment scheduling.

The project is positioned as an all-in-one healthcare platform. The current codebase implements the foundation modules and presents additional ERP modules on the marketing page as product capabilities or roadmap scope.

## 2. Product Goals

- Provide a modern web interface for healthcare facility operations.
- Centralize patient information, guardian contact details, and appointment scheduling.
- Support clinic staff, doctors, admins, and custom operational roles.
- Prepare the product for expansion into full hospital ERP workflows such as lab, pharmacy, billing, inventory, surgery, radiology, telemedicine, and AI-assisted consultation.
- Deploy as a Cloudflare Worker powered TanStack Start application with Supabase as the backend.

## 3. Current Implementation Status

Implemented:

- Public landing page.
- CareOrbit branding and Ecliptix-inspired dark blue/purple visual theme.
- Email/password login.
- Email/password signup.
- Password strength checklist.
- Show/hide password controls.
- Random strong password suggestion.
- Role selection during signup.
- Protected authenticated layout.
- Dashboard with counts.
- Patient listing, search, and creation.
- Guardian emergency contact capture for patients.
- Appointment listing and scheduling.
- Patient problem/disease brief on appointments.
- Supabase database schema, types, RLS policies, and auth trigger.
- Cloudflare Worker build/deployment configuration.

Not currently exposed in the UI:

- Google login, OTP login, and email verification UI.
- Patient edit/delete screens.
- Appointment edit/delete/status update screens.
- Full role-specific dashboards.
- Multi-facility tenant separation.
- Lab, pharmacy, billing, inventory, surgery, radiology, telemedicine, and AI modules beyond marketing content.

## 4. Target Users and Roles

### 4.1 Admin

Expected responsibilities:

- Manage facility-level data.
- Manage user roles.
- Delete records where allowed by backend policy.
- View all patients and appointments.

Current implementation:

- Admin can be selected during signup.
- Backend role is stored in `user_roles`.
- Backend RLS allows admins to delete patients and appointments.
- No admin-only management UI is currently implemented.

### 4.2 Doctor

Expected responsibilities:

- View patient context.
- Review appointments.
- Use problem/disease brief before consultation.
- Create or update clinical workflow records.

Current implementation:

- Doctor can be selected during signup.
- Doctors can view patients and appointments through authenticated access.
- Appointment creation stores `doctor_id` as the current user.

### 4.3 Staff

Expected responsibilities:

- Register patients.
- Capture contact and guardian details.
- Schedule appointments.
- Support front desk workflows.

Current implementation:

- Staff is the default signup role.
- Staff can create patients and appointments.
- Staff can update records by backend policy, though edit UI is not currently present.

### 4.4 Custom Role

Expected examples:

- Pharmacist.
- Lab technician.
- Billing operator.
- Nurse.
- Radiology technician.

Current implementation:

- Signup supports `custom` role.
- User enters a custom label.
- Backend stores the custom label in `profiles.custom_role_label` and `user_roles.custom_label`.

## 5. Route Map

### Public Routes

| Route | Purpose | Access |
| --- | --- | --- |
| `/` | Landing page with product overview, features, why choose us, CTA, footer | Public |
| `/login` | Email/password login | Public, redirects authenticated users to dashboard |
| `/signup` | Account creation form | Public |

### Authenticated Routes

| Route | Purpose | Access |
| --- | --- | --- |
| `/dashboard` | Operational overview | Authenticated users |
| `/patients` | Patient list, search, and add patient modal | Authenticated users |
| `/appointments` | Appointment list and new appointment modal | Authenticated users |

Authenticated routes are implemented under the TanStack Router `_authenticated` layout. If no user session exists, the app redirects to `/login`.

## 6. Functional Specification

### 6.1 Landing Page

File: `src/routes/index.tsx`

Purpose:

- Present CareOrbit as an intuitive healthcare ERP, EMR, and AI platform.
- Drive visitors to create an account or sign in.
- Explain product features and reasons to choose the platform.

Sections:

- Sticky header with CareOrbit logo.
- Navigation links:
  - Features.
  - Why Choose Us.
  - Contact.
- Hero section:
  - Product headline.
  - Supporting copy.
  - `Book a demo` CTA to `/signup`.
  - `Explore features` anchor to `#features`.
  - Healthcare-oriented trust indicators.
  - Doctor/tablet hero image.
- Features section:
  - Patient Management.
  - IPD / OPD Management.
  - Medical Staff.
  - Quick Consultations.
  - AI & Voice Consultation.
  - Lab Management.
  - Pharmacy.
  - Billing & Accounting.
  - Inventory.
  - Surgery.
  - Radiology & DICOM.
  - Telemedicine.
- Why Choose Us section:
  - Stats cards.
  - Trust/access control message.
  - Care coordination message.
  - Healthcare team fit.
  - AI-ready operations.
- Contact/CTA section:
  - Create account.
  - Sign in.
- Footer:
  - CareOrbit copyright.
  - `www.careorbit.in`.
  - `sales@careorbit.in`.

Acceptance criteria:

- Public page loads without authentication.
- Header brand displays `CareOrbit`.
- Features and Why Choose Us navigate to separate sections.
- Signup and login CTAs route correctly.
- Page title is `CareOrbit - Intuitive Healthcare ERP + EMR + AI`.

### 6.2 Authentication

Files:

- `src/routes/login.tsx`
- `src/routes/signup.tsx`
- `src/hooks/use-auth.ts`
- `src/integrations/supabase/client.ts`

Current authentication method:

- Supabase email/password authentication.

Removed from UI:

- Google auth button.
- OTP auth flow.
- Email verification prompt/wording.

Login requirements:

- User enters email and password.
- Password field supports show/hide.
- Existing authenticated users are redirected to `/dashboard`.
- Login uses `supabase.auth.signInWithPassword`.
- Success displays a toast and navigates to dashboard.
- Failure displays Supabase error text in a toast.

Signup requirements:

- User enters:
  - Full name.
  - Organization.
  - Role.
  - Optional custom role label.
  - Email.
  - Password.
- Password must pass all checks:
  - At least 8 characters.
  - One uppercase letter.
  - One lowercase letter.
  - One number.
  - One special character.
- Signup submit is disabled until the password is strong.
- Password field supports show/hide.
- Suggest button generates a strong random password and shows it.
- Signup sends metadata to Supabase:
  - `full_name`.
  - `organization`.
  - `role`.
  - `custom_role_label`.
- If Supabase does not return a session, the app attempts immediate email/password sign-in.
- On success, user is navigated to `/dashboard`.

Session handling:

- `useAuth` subscribes to Supabase auth state.
- Session persists in browser `localStorage`.
- Supabase client auto-refreshes tokens.

Acceptance criteria:

- Weak passwords cannot submit signup.
- Strong suggested password enables signup.
- Show/hide password toggles field type.
- Google/OTP/email verification UI is not visible.
- Sign out clears the Supabase session and returns to `/`.

### 6.3 Authenticated App Shell

Files:

- `src/routes/_authenticated.tsx`
- `src/components/app-shell.tsx`

Purpose:

- Protect application routes.
- Provide persistent navigation for logged-in users.

Desktop layout:

- Left sidebar.
- CareOrbit logo.
- Navigation:
  - Overview.
  - Patients.
  - Appointments.
- Sign out button.

Mobile layout:

- Top bar with CareOrbit.
- Horizontal navigation.
- Sign out icon button.

Access behavior:

- While auth status is loading, show a centered loading icon.
- If no user is present, navigate to `/login`.
- If user is present, render nested route content.

Acceptance criteria:

- Unauthenticated access to `/dashboard`, `/patients`, or `/appointments` redirects to login.
- Authenticated users see the app shell.
- Active navigation item is highlighted.
- Sign out returns the user to the public home page.

### 6.4 Dashboard

File: `src/routes/_authenticated/dashboard.tsx`

Purpose:

- Give logged-in users a quick operational snapshot.

Displayed data:

- Total patients.
- Total appointments.
- Today's appointments.
- Active modules count, currently hardcoded as `12`.
- Greeting based on `profiles.full_name`.
- Organization name based on `profiles.organization`.

Data sources:

- `patients` table count.
- `appointments` table count.
- `appointments` count between start and end of current day.
- `profiles` table for current user.

Acceptance criteria:

- Dashboard loads only for authenticated users.
- Counts are fetched from Supabase.
- User greeting uses first name when available.
- Organization fallback is `Your facility`.

### 6.5 Patient Management

File: `src/routes/_authenticated/patients.tsx`

Purpose:

- Manage patient records.
- Capture guardian emergency contact.
- Support front desk search.

List behavior:

- Fetches all patients from Supabase.
- Orders by `created_at` descending.
- Displays table columns:
  - MRN.
  - Name.
  - DOB.
  - Phone.
  - Guardian.
  - Blood group.
- Shows empty state if there are no records.
- Shows loading state while fetching.

Search behavior:

- Search input filters client-side by:
  - Patient full name.
  - MRN.
  - Guardian emergency contact.

Create patient behavior:

- `New patient` opens a modal form.
- Required field:
  - Full name.
- Optional fields:
  - Date of birth.
  - Gender.
  - Phone.
  - Guardian emergency contact.
  - Email.
  - Blood group.
  - Allergies.
  - Address.
  - Notes.
- On submit, record is inserted into `patients`.
- `created_by` is set to the current authenticated user's ID.
- Success invalidates the patient query and closes the modal.

Guardian emergency contact storage:

- There is no separate database column for guardian emergency contact.
- The UI stores it inside `patients.notes` using this prefix:
  - `Guardian emergency contact:`
- The list extracts guardian contact from notes using that prefix.

Recommended future change:

- Add a dedicated `guardian_emergency_contact` column to `patients` to avoid storing structured data inside free-text notes.

Acceptance criteria:

- New patient can be created with full name only.
- MRN is generated by the database if not supplied.
- Guardian contact appears in the patient table.
- Search by name, MRN, or guardian contact works.
- Errors show as toasts.

### 6.6 Appointment Scheduling

File: `src/routes/_authenticated/appointments.tsx`

Purpose:

- Schedule and track consultations.
- Capture patient problem/disease brief for doctor preparation.

List behavior:

- Fetches appointments from Supabase.
- Joins each appointment with patient name and MRN.
- Orders appointments by `scheduled_at` ascending.
- Displays table columns:
  - When.
  - Patient.
  - Problem / disease brief.
  - Status.
- Displays empty state if no appointments exist.

Patient prerequisite:

- Appointment creation requires at least one patient.
- If no patients exist, the page shows `Add a patient first to schedule appointments.`
- `New appointment` is disabled while there are no patients.

Create appointment behavior:

- `New appointment` opens a modal form.
- Required fields:
  - Patient.
  - Date and time.
- Optional/default fields:
  - Duration in minutes, default `30`.
  - Patient problem/disease brief.
  - Status defaults to `scheduled`.
- On submit:
  - `scheduled_at` is converted to ISO string.
  - `duration_minutes` is converted to number.
  - `doctor_id` is set to current user ID.
  - `created_by` is set to current user ID.
- Success invalidates appointment query and closes modal.

Appointment statuses:

- `scheduled`
- `confirmed`
- `completed`
- `cancelled`
- `no_show`

Current limitation:

- UI creates appointments with `scheduled` status only.
- UI does not currently expose status change, edit, or delete actions.

Acceptance criteria:

- User cannot schedule appointment without a selected patient.
- Appointment appears in the appointment table after creation.
- Problem/disease brief displays in the appointment row.
- Status badge styling reflects appointment status.

## 7. Data Model

Database provider: Supabase Postgres.

Generated TypeScript types: `src/integrations/supabase/types.ts`.

Migrations:

- `supabase/migrations/20260508163603_14ab6362-a493-4348-a89a-4658d052f258.sql`
- `supabase/migrations/20260508163631_c6817d6a-793a-49a2-932e-ab12ad829c29.sql`
- `supabase/migrations/20260508163705_228cfa22-f3bd-4364-87bd-aa25a55735ac.sql`

### 7.1 Enums

`app_role`:

- `admin`
- `doctor`
- `staff`
- `custom`

`appointment_status`:

- `scheduled`
- `confirmed`
- `completed`
- `cancelled`
- `no_show`

### 7.2 `profiles`

Purpose:

- Store application profile information for each Supabase auth user.

Columns:

- `id`: UUID primary key, references `auth.users(id)`, cascade delete.
- `full_name`: text.
- `phone`: text.
- `organization`: text.
- `custom_role_label`: text.
- `avatar_url`: text.
- `created_at`: timestamp with timezone, default now.
- `updated_at`: timestamp with timezone, default now.

RLS:

- Authenticated users can select profiles.
- Users can insert their own profile.
- Users can update their own profile.

### 7.3 `user_roles`

Purpose:

- Store one or more roles for each user.

Columns:

- `id`: UUID primary key, default generated.
- `user_id`: UUID, references `auth.users(id)`, cascade delete.
- `role`: `app_role`.
- `custom_label`: text.
- `created_at`: timestamp with timezone, default now.

Constraints:

- Unique combination of `user_id`, `role`, and `custom_label`.

RLS:

- Users can view their own roles.
- Admins can view all roles.
- Admins can manage roles.

Helper function:

- `public.has_role(_user_id uuid, _role app_role)` returns boolean.

### 7.4 `patients`

Purpose:

- Store patient demographic and clinical context.

Columns:

- `id`: UUID primary key, default generated.
- `mrn`: unique text, default format `MRN-XXXXXXXX`.
- `full_name`: text, required.
- `date_of_birth`: date.
- `gender`: text.
- `phone`: text.
- `email`: text.
- `address`: text.
- `blood_group`: text.
- `allergies`: text.
- `notes`: text.
- `created_by`: UUID, references `auth.users(id)`, set null on user delete.
- `created_at`: timestamp with timezone, default now.
- `updated_at`: timestamp with timezone, default now.

RLS:

- Authenticated users can view patients.
- Authenticated users can insert patients where `auth.uid() = created_by`.
- Admin, doctor, staff, and custom roles can update patients.
- Admins can delete patients.

Current production concern:

- All authenticated users can currently view all patients. For multi-clinic production use, RLS should be extended with facility/organization tenancy.

### 7.5 `appointments`

Purpose:

- Store scheduled patient consultations.

Columns:

- `id`: UUID primary key, default generated.
- `patient_id`: UUID, required, references `patients(id)`, cascade delete.
- `doctor_id`: UUID, references `auth.users(id)`, set null on user delete.
- `scheduled_at`: timestamp with timezone, required.
- `duration_minutes`: integer, required, default `30`.
- `reason`: text.
- `status`: `appointment_status`, required, default `scheduled`.
- `notes`: text.
- `created_by`: UUID, references `auth.users(id)`, set null on user delete.
- `created_at`: timestamp with timezone, default now.
- `updated_at`: timestamp with timezone, default now.

RLS:

- Authenticated users can view appointments.
- Authenticated users can insert appointments where `auth.uid() = created_by`.
- Admin, doctor, staff, and custom roles can update appointments.
- Admins can delete appointments.

Relationship:

- `appointments.patient_id` points to `patients.id`.

Current production concern:

- All authenticated users can currently view all appointments. For multi-clinic production use, RLS should be extended with facility/organization tenancy.

### 7.6 Triggers and Functions

`handle_updated_at`:

- Automatically updates `updated_at` before update on profiles, patients, and appointments.

`handle_new_user`:

- Runs after insert on `auth.users`.
- Creates a row in `profiles`.
- Reads signup metadata:
  - `full_name`.
  - `organization`.
  - `role`.
  - `custom_role_label`.
- Creates a corresponding row in `user_roles`.

Security hardening migration:

- Revokes public, anon, and authenticated direct execution access for security definer functions.

## 8. UI and Design Specification

### 8.1 Branding

Brand name:

- CareOrbit

Page title:

- `CareOrbit - Intuitive Healthcare ERP + EMR + AI`

Logo treatment:

- Activity icon in a gradient square.
- Text lockup: `Care` + gradient `Orbit`.

### 8.2 Theme

The UI uses a dark, technology-oriented theme inspired by Ecliptix-style blue/purple color combinations.

Primary visual tokens:

- Background: dark blue-black.
- Primary: electric blue.
- Secondary/accent: blue-purple.
- Brand gradient: electric blue to violet.
- Cards: dark gradient panels.
- Borders: translucent white.
- Shadows: blue glow and elevated cards.

Main CSS file:

- `src/styles.css`

Utility classes:

- `.bg-gradient-hero`
- `.bg-gradient-brand`
- `.bg-gradient-card`
- `.text-gradient-brand`
- `.shadow-glow`
- `.shadow-elegant`

### 8.3 Component System

UI components:

- Shadcn/Radix style components in `src/components/ui`.
- Lucide icons.
- Tailwind CSS v4 variables.

Component conventions:

- Cards use rounded corners and dark surface treatment.
- Primary CTAs use `bg-gradient-brand`.
- Toasts use `sonner`.
- Responsive navigation switches between sidebar and mobile top navigation.

### 8.4 Responsiveness

Expected behavior:

- Public site supports mobile and desktop layouts.
- Authenticated app uses desktop sidebar on `md` and above.
- Authenticated app uses mobile top bar and horizontal nav below `md`.
- Tables hide lower-priority columns on smaller screens.

## 9. Technical Architecture

### 9.1 Frontend

Framework:

- React 19.
- TanStack Start.
- TanStack Router.
- TanStack Query.
- Vite.
- TypeScript.

Styling:

- Tailwind CSS v4.
- CSS variables.
- Radix UI primitives.
- Shadcn-compatible component structure.

Data fetching:

- React Query handles Supabase read and mutation calls.
- Query invalidation refreshes lists after creation.

Routing:

- File-based TanStack Router routes.
- Generated route tree at `src/routeTree.gen.ts`.

### 9.2 Backend and Database

Backend service:

- Supabase Auth.
- Supabase Postgres.
- Supabase Row Level Security.

Client integration:

- Browser client: `src/integrations/supabase/client.ts`.
- Server admin client: `src/integrations/supabase/client.server.ts`.
- Auth middleware helper: `src/integrations/supabase/auth-middleware.ts`.

Important environment variables:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Service role warning:

- `SUPABASE_SERVICE_ROLE_KEY` must only be used server-side.
- It must never be exposed to client code.

### 9.3 Runtime and Deployment

Target runtime:

- Cloudflare Workers.

Config:

- `wrangler.jsonc`
- `vite.config.ts`

Cloudflare settings:

- Compatibility date: `2025-09-24`.
- Compatibility flag: `nodejs_compat`.
- Worker main entry: `src/server.ts`.

Build output:

- Client assets: `dist/client`.
- Server worker bundle: `dist/server`.
- Worker deploy config generated at `dist/server/wrangler.json`.

Recommended future deployment rename:

- Rename any legacy Worker/project URLs and upload artifacts to `careorbit` to match current branding.

## 10. Error Handling

Files:

- `src/server.ts`
- `src/start.ts`
- `src/lib/error-capture.ts`
- `src/lib/error-page.ts`
- `src/routes/__root.tsx`

Client route error handling:

- TanStack Router root route defines:
  - Not found component.
  - Error component with retry and home action.

Server error handling:

- `src/start.ts` wraps request handling and returns a branded error page on unexpected errors.
- `src/server.ts` wraps the TanStack Start server entry.
- Catastrophic SSR JSON 500 responses are normalized into a user-friendly HTML error page.
- Recent unhandled errors are captured for logging.

User feedback:

- Auth, patient, and appointment operations use `sonner` toast notifications.

## 11. Security Specification

Authentication:

- Supabase email/password auth.
- Persistent sessions in browser local storage.
- Auto token refresh enabled.

Authorization:

- Route protection is client-side in `_authenticated`.
- Database protection is enforced by Supabase RLS.
- Roles are stored in `user_roles`.

Data protection:

- RLS is enabled on `profiles`, `user_roles`, `patients`, and `appointments`.
- Insert policies require `created_by` to match the authenticated user for patients and appointments.
- Delete policies are admin-only for patients and appointments.

Current security gaps before production:

- Multi-tenant data isolation is not implemented. Any authenticated user can currently select all patients and appointments.
- Role-specific UI restrictions are not implemented.
- Sensitive healthcare data should have audit logs before production use.
- A dedicated guardian contact column should replace parsing from notes.
- Privacy/compliance claims require legal and operational review before production marketing.

## 12. Testing Specification

### 12.1 Build and Static Checks

Required commands:

```powershell
npm run lint
npm run build
```

Expected result:

- Lint exits with no errors.
- Build exits successfully.
- Existing Fast Refresh warnings in shared UI components may appear unless refactored.

### 12.2 Smoke Test Cases

Public:

- Home page loads.
- Header displays CareOrbit.
- Features link scrolls/navigates to features section.
- Why Choose Us link scrolls/navigates to why section.
- Contact link scrolls/navigates to CTA section.
- Login CTA opens login page.
- Signup CTA opens signup page.

Authentication:

- Login form renders.
- Password show/hide works.
- Invalid login shows error toast.
- Signup form renders.
- Weak password disables submit.
- Strong password enables submit.
- Suggest password generates a valid strong password.
- Google/OTP/email verification UI is not visible.

Authenticated:

- Unauthenticated `/dashboard` redirects to login.
- Authenticated `/dashboard` displays metric cards.
- Authenticated `/patients` displays patient page.
- Authenticated `/appointments` displays appointment page.
- Sign out returns to home.

Patients:

- Add patient modal opens.
- Required full name validation works.
- Patient saves successfully.
- Patient table refreshes.
- Guardian emergency contact displays in table.
- Search works for name, MRN, and guardian contact.

Appointments:

- New appointment button is disabled when no patients exist.
- After creating a patient, new appointment can be opened.
- Patient selector lists patients.
- Date/time is required.
- Problem/disease brief saves into `reason`.
- Appointment appears in the table.

Responsive:

- Landing page works on mobile and desktop.
- Authenticated sidebar appears on desktop.
- Mobile top navigation appears on mobile.
- Tables remain readable with hidden columns on smaller screens.

### 12.3 Regression Checks

- Search for previous branding:

```powershell
rg -n "previous-brand-name" src dist
```

Expected result:

- No previous brand matches after the CareOrbit rename.

## 13. Development Workflow

Install dependencies:

```powershell
npm install
```

Run local development server:

```powershell
npm run dev
```

Build production output:

```powershell
npm run build
```

Preview build:

```powershell
npm run preview
```

Lint:

```powershell
npm run lint
```

Format:

```powershell
npm run format
```

## 14. Deployment Workflow

Production build:

```powershell
npm run build
```

Cloudflare deploy:

```powershell
wrangler deploy --config .\dist\server\wrangler.json --name careorbit-erp-test
```

Current project still contains earlier deployment naming artifacts.

Recommended cleanup:

- Rename deployment artifacts and worker names to CareOrbit before final production launch.

## 15. Future Scope

Near-term:

- Dedicated edit/delete UI for patients.
- Dedicated edit/delete/status update UI for appointments.
- Facility/organization table.
- Tenant-aware RLS on patients and appointments.
- Role-based UI permissions.
- Profile page.
- Admin user management.
- Audit log table.
- Dedicated guardian emergency contact column.
- Appointment filters by date, doctor, status, and patient.

Medium-term:

- OPD/IPD workflows.
- Doctor scheduling.
- Medical staff management.
- Lab orders and lab results.
- Pharmacy inventory and dispensing.
- Billing/invoicing.
- Inventory and expiry management.
- Surgery/OT scheduling.
- Radiology and DICOM workflow.
- Telemedicine appointments.

Long-term:

- AI consultation assistant.
- Voice receptionist.
- Clinical templates.
- Automated follow-up reminders.
- Analytics dashboards.
- Multi-branch hospital group support.
- Compliance documentation and audit exports.

## 16. Acceptance Criteria for Current Release

The current release is acceptable when:

- Public landing page renders with CareOrbit branding.
- Login/signup work with email/password only.
- Weak signup passwords are blocked.
- Strong password suggestion works.
- Protected routes redirect unauthenticated users.
- Authenticated users can view dashboard.
- Authenticated users can create and search patients.
- Guardian emergency contact is captured and displayed.
- Authenticated users can schedule appointments.
- Patient problem/disease brief appears in appointment list.
- No previous brand naming remains in active source/build output.
- `npm run lint` has no errors.
- `npm run build` completes successfully.

## 17. Key Files

| File | Purpose |
| --- | --- |
| `src/routes/index.tsx` | Public landing page |
| `src/routes/login.tsx` | Login UI and flow |
| `src/routes/signup.tsx` | Signup UI, role selection, password rules |
| `src/routes/_authenticated.tsx` | Protected route wrapper |
| `src/routes/_authenticated/dashboard.tsx` | Dashboard metrics |
| `src/routes/_authenticated/patients.tsx` | Patient list/search/create |
| `src/routes/_authenticated/appointments.tsx` | Appointment list/create |
| `src/components/site-header.tsx` | Public header |
| `src/components/app-shell.tsx` | Authenticated navigation shell |
| `src/styles.css` | Theme tokens and utilities |
| `src/hooks/use-auth.ts` | Supabase session hook |
| `src/integrations/supabase/client.ts` | Browser Supabase client |
| `src/integrations/supabase/client.server.ts` | Server admin Supabase client |
| `src/integrations/supabase/auth-middleware.ts` | Bearer token auth middleware |
| `src/integrations/supabase/types.ts` | Generated database types |
| `supabase/migrations/*.sql` | Database schema, RLS, triggers |
| `src/server.ts` | Cloudflare/TanStack server wrapper |
| `src/start.ts` | TanStack Start setup and error middleware |
| `wrangler.jsonc` | Cloudflare Worker config |
| `vite.config.ts` | TanStack Start/Vite config |
