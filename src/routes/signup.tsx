import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { databaseRoleFor, signupRoleOptions, type RoleKey } from "@/lib/access-control";

export const Route = createFileRoute("/signup")({
  component: SignupPage,
});

const passwordRules = [
  { label: "At least 8 characters", test: (value: string) => value.length >= 8 },
  { label: "One uppercase letter", test: (value: string) => /[A-Z]/.test(value) },
  { label: "One lowercase letter", test: (value: string) => /[a-z]/.test(value) },
  { label: "One number", test: (value: string) => /\d/.test(value) },
  { label: "One special character", test: (value: string) => /[^A-Za-z0-9]/.test(value) },
];

const passwordCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*?";

function getPasswordChecks(password: string) {
  return passwordRules.map((rule) => ({ ...rule, passed: rule.test(password) }));
}

function getRandomIndex(length: number) {
  const values = new Uint32Array(1);
  crypto.getRandomValues(values);
  return values[0] % length;
}

function generateStrongPassword() {
  const requiredCharacters = ["A", "z", "7", "!"];
  const remainingCharacters = Array.from({ length: 10 }, () => {
    return passwordCharacters[getRandomIndex(passwordCharacters.length)];
  });

  return [...requiredCharacters, ...remainingCharacters]
    .map((character) => ({ character, sort: getRandomIndex(1000) }))
    .sort((a, b) => a.sort - b.sort)
    .map(({ character }) => character)
    .join("");
}

function SignupPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState<1 | 2>(1);
  const [role, setRole] = useState<RoleKey>("staff");
  const [fullName, setFullName] = useState("");
  const [organization, setOrganization] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  const handleSubmit = async () => {
    const trimmedFullName = fullName.trim();
    const trimmedOrganization = organization.trim();
    const trimmedEmail = email.trim();

    if (!trimmedFullName || !trimmedEmail || !password) {
      setErrorMessage("Please fill the required fields");
      toast.error("Please fill the required fields");
      return;
    }

    const isPasswordStrong = getPasswordChecks(password).every((rule) => rule.passed);
    if (!isPasswordStrong) {
      setErrorMessage("Password does not meet all strength requirements");
      toast.error("Password does not meet all strength requirements");
      return;
    }

    setLoading(true);
    setErrorMessage("");
    const requestedRole = databaseRoleFor(role);
    const { data, error } = await supabase.auth.signUp({
      email: trimmedEmail,
      password,
      options: {
        data: {
          full_name: trimmedFullName,
          organization: trimmedOrganization,
          role: requestedRole.role,
          requested_role: role,
          custom_role_label: requestedRole.custom_label,
        },
      },
    });
    setLoading(false);

    if (error) {
      setErrorMessage(error.message);
      toast.error(error.message);
      return;
    }

    if (!data.session) {
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: trimmedEmail,
        password,
      });
      if (signInError) {
        setErrorMessage("Account created. Please sign in with the same email and password.");
        toast.success("Account created. Please sign in.");
        navigate({ to: "/login" });
        return;
      }
    }

    toast.success("Account created");
    navigate({ to: "/dashboard" });
  };

  const handleSuggestPassword = () => {
    setPassword(generateStrongPassword());
    toast.success("Strong password generated");
  };

  const goToCredentialsStep = () => {
    if (!fullName.trim()) {
      setErrorMessage("Please enter your full name");
      toast.error("Please enter your full name");
      return;
    }

    setErrorMessage("");
    setStep(2);
  };

  return (
    <div className="min-h-screen bg-background px-4 py-10 text-foreground">
      <div className="mx-auto max-w-md rounded-xl border border-border bg-card p-6">
        <Link to="/" className="mb-4 inline-block text-sm text-primary">
          CareOrbit
        </Link>
        <h1 className="text-2xl font-semibold">Create your account</h1>
        <p className="mt-1 text-sm text-muted-foreground">Start managing your facility today</p>
        <div className="mt-4 text-xs text-muted-foreground">Step {step} of 2</div>

        <form
          className="mt-6 space-y-4"
          autoComplete="on"
          onSubmit={(event) => {
            event.preventDefault();
            void handleSubmit();
          }}
        >
          {step === 1 ? (
            <>
              <div>
                <label htmlFor="name" className="mb-1 block text-sm font-medium">
                  Full name
                </label>
                <input
                  id="name"
                  name="name"
                  value={fullName}
                  onChange={(event) => setFullName(event.target.value)}
                  autoComplete="name"
                  className="h-10 w-full rounded-md border border-border bg-background px-3 text-sm outline-none"
                />
              </div>

              <div>
                <label htmlFor="org" className="mb-1 block text-sm font-medium">
                  Organization
                </label>
                <input
                  id="org"
                  name="organization"
                  value={organization}
                  onChange={(event) => setOrganization(event.target.value)}
                  autoComplete="organization"
                  placeholder="Clinic / Hospital name"
                  className="h-10 w-full rounded-md border border-border bg-background px-3 text-sm outline-none"
                />
              </div>

              <div>
                <label htmlFor="role" className="mb-1 block text-sm font-medium">
                  Your role
                </label>
                <select
                  id="role"
                  name="role"
                  aria-label="Your role"
                  value={role}
                  onChange={(e) => {
                    setRole(e.target.value as RoleKey);
                    setErrorMessage("");
                  }}
                  className="h-10 w-full rounded-md border border-border bg-background px-3 text-sm outline-none"
                >
                  {signupRoleOptions.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </select>
                <p className="mt-2 text-xs text-muted-foreground">
                  For testing, accounts are approved immediately with the selected role rights.
                </p>
              </div>
            </>
          ) : (
            <>
              <div>
                <label htmlFor="email" className="mb-1 block text-sm font-medium">
                  Email
                </label>
                <input
                  id="email"
                  name="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  type="email"
                  autoComplete="email"
                  autoCapitalize="none"
                  autoCorrect="off"
                  className="h-10 w-full rounded-md border border-border bg-background px-3 text-sm outline-none"
                />
              </div>

              <div>
                <div className="mb-1 flex items-center justify-between gap-3">
                  <label htmlFor="password" className="block text-sm font-medium">
                    Password
                  </label>
                  <button
                    type="button"
                    className="text-xs text-primary"
                    onClick={handleSuggestPassword}
                  >
                    Suggest
                  </button>
                </div>
                <input
                  id="password"
                  name="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  type="password"
                  autoComplete="new-password"
                  autoCapitalize="none"
                  autoCorrect="off"
                  spellCheck={false}
                  className="h-10 w-full rounded-md border border-border bg-background px-3 text-sm outline-none"
                />
                <div className="mt-3 rounded-md border border-border bg-muted/30 p-3 text-xs text-muted-foreground">
                  <div className="mb-2 font-medium text-foreground">Password requirements</div>
                  <ul className="grid gap-1.5">
                    {passwordRules.map((rule) => (
                      <li key={rule.label}>{rule.label}</li>
                    ))}
                  </ul>
                </div>
              </div>
            </>
          )}

          {errorMessage && (
            <div className="rounded-md border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
              {errorMessage}
            </div>
          )}

          <div className="flex gap-3">
            {step === 2 && (
              <button
                type="button"
                disabled={loading}
                onClick={() => {
                  setErrorMessage("");
                  setStep(1);
                }}
                className="h-10 flex-1 rounded-md border border-border bg-background text-sm font-medium"
              >
                Back
              </button>
            )}

            {step === 1 ? (
              <button
                type="button"
                onClick={goToCredentialsStep}
                className="h-10 flex-1 rounded-md bg-primary text-sm font-medium text-primary-foreground"
              >
                Continue
              </button>
            ) : (
              <button
                type="submit"
                disabled={loading}
                className="h-10 flex-1 rounded-md bg-primary text-sm font-medium text-primary-foreground"
              >
                {loading ? "Creating..." : "Create account"}
              </button>
            )}
          </div>
        </form>

        <p className="mt-6 text-sm text-muted-foreground">
          Already have an account?{" "}
          <Link to="/login" className="text-primary underline-offset-4 hover:underline">
            Sign in
          </Link>
        </p>
      </div>
    </div>
  );
}
