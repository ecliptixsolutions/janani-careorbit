import { describe, expect, it } from "vitest";
import {
  databaseRoleFor,
  pickPrimaryRole,
  roleDefinitions,
  roleFromRow,
  signupRoleOptions,
} from "./access-control";

describe("role access control", () => {
  it("keeps privileged actions limited to administrators", () => {
    const privileged = ["super_admin", "hospital_admin", "admin"] as const;
    const nonPrivileged = [
      "doctor",
      "staff",
      "nurse",
      "pharmacist",
      "lab_technician",
      "billing_operator",
      "custom",
      "pending",
    ] as const;

    for (const role of privileged) {
      expect(roleDefinitions[role].permissions.canManageUsers).toBe(true);
      expect(roleDefinitions[role].permissions.canManageRoles).toBe(true);
      expect(roleDefinitions[role].permissions.canDeleteRecords).toBe(true);
    }

    for (const role of nonPrivileged) {
      expect(roleDefinitions[role].permissions.canManageUsers).toBe(false);
      expect(roleDefinitions[role].permissions.canManageRoles).toBe(false);
      expect(roleDefinitions[role].permissions.canDeleteRecords).toBe(false);
    }
  });

  it("maps every sign-up role to its persisted role identity", () => {
    for (const option of signupRoleOptions) {
      const stored = databaseRoleFor(option.value);
      expect(roleFromRow(stored).key).toBe(option.value);
    }
  });

  it("selects the highest-priority role deterministically", () => {
    const role = pickPrimaryRole([
      {
        id: "staff",
        user_id: "user",
        role: "staff",
        custom_label: null,
        created_at: "2026-07-04T00:00:00Z",
      },
      {
        id: "admin",
        user_id: "user",
        role: "admin",
        custom_label: "hospital_admin",
        created_at: "2026-07-04T00:00:00Z",
      },
      {
        id: "doctor",
        user_id: "user",
        role: "doctor",
        custom_label: null,
        created_at: "2026-07-04T00:00:00Z",
      },
    ]);

    expect(role.key).toBe("hospital_admin");
  });
});
