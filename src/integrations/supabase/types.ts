export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5";
  };
  public: {
    Tables: {
      appointments: {
        Row: {
          created_at: string;
          created_by: string | null;
          doctor_id: string | null;
          duration_minutes: number;
          id: string;
          notes: string | null;
          patient_id: string;
          reason: string | null;
          scheduled_at: string;
          status: Database["public"]["Enums"]["appointment_status"];
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          doctor_id?: string | null;
          duration_minutes?: number;
          id?: string;
          notes?: string | null;
          patient_id: string;
          reason?: string | null;
          scheduled_at: string;
          status?: Database["public"]["Enums"]["appointment_status"];
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          doctor_id?: string | null;
          duration_minutes?: number;
          id?: string;
          notes?: string | null;
          patient_id?: string;
          reason?: string | null;
          scheduled_at?: string;
          status?: Database["public"]["Enums"]["appointment_status"];
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "appointments_patient_id_fkey";
            columns: ["patient_id"];
            isOneToOne: false;
            referencedRelation: "patients";
            referencedColumns: ["id"];
          },
        ];
      };
      notifications: {
        Row: {
          actor_id: string | null;
          appointment_id: string | null;
          body: string;
          channel: string;
          created_at: string;
          id: string;
          metadata: Json;
          patient_id: string | null;
          read_at: string | null;
          recipient_id: string | null;
          recipient_phone: string | null;
          title: string;
        };
        Insert: {
          actor_id?: string | null;
          appointment_id?: string | null;
          body: string;
          channel?: string;
          created_at?: string;
          id?: string;
          metadata?: Json;
          patient_id?: string | null;
          read_at?: string | null;
          recipient_id?: string | null;
          recipient_phone?: string | null;
          title: string;
        };
        Update: {
          actor_id?: string | null;
          appointment_id?: string | null;
          body?: string;
          channel?: string;
          created_at?: string;
          id?: string;
          metadata?: Json;
          patient_id?: string | null;
          read_at?: string | null;
          recipient_id?: string | null;
          recipient_phone?: string | null;
          title?: string;
        };
        Relationships: [
          {
            foreignKeyName: "notifications_appointment_id_fkey";
            columns: ["appointment_id"];
            isOneToOne: false;
            referencedRelation: "appointments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_patient_id_fkey";
            columns: ["patient_id"];
            isOneToOne: false;
            referencedRelation: "patients";
            referencedColumns: ["id"];
          },
        ];
      };
      patients: {
        Row: {
          address: string | null;
          allergies: string | null;
          blood_group: string | null;
          created_at: string;
          created_by: string | null;
          date_of_birth: string | null;
          email: string | null;
          full_name: string;
          gender: string | null;
          id: string;
          mrn: string;
          notes: string | null;
          phone: string | null;
          updated_at: string;
        };
        Insert: {
          address?: string | null;
          allergies?: string | null;
          blood_group?: string | null;
          created_at?: string;
          created_by?: string | null;
          date_of_birth?: string | null;
          email?: string | null;
          full_name: string;
          gender?: string | null;
          id?: string;
          mrn?: string;
          notes?: string | null;
          phone?: string | null;
          updated_at?: string;
        };
        Update: {
          address?: string | null;
          allergies?: string | null;
          blood_group?: string | null;
          created_at?: string;
          created_by?: string | null;
          date_of_birth?: string | null;
          email?: string | null;
          full_name?: string;
          gender?: string | null;
          id?: string;
          mrn?: string;
          notes?: string | null;
          phone?: string | null;
          updated_at?: string;
        };
        Relationships: [];
      };
      profiles: {
        Row: {
          avatar_url: string | null;
          created_at: string;
          custom_role_label: string | null;
          full_name: string | null;
          id: string;
          organization: string | null;
          phone: string | null;
          updated_at: string;
        };
        Insert: {
          avatar_url?: string | null;
          created_at?: string;
          custom_role_label?: string | null;
          full_name?: string | null;
          id: string;
          organization?: string | null;
          phone?: string | null;
          updated_at?: string;
        };
        Update: {
          avatar_url?: string | null;
          created_at?: string;
          custom_role_label?: string | null;
          full_name?: string | null;
          id?: string;
          organization?: string | null;
          phone?: string | null;
          updated_at?: string;
        };
        Relationships: [];
      };
      user_roles: {
        Row: {
          created_at: string;
          custom_label: string | null;
          id: string;
          role: Database["public"]["Enums"]["app_role"];
          user_id: string;
        };
        Insert: {
          created_at?: string;
          custom_label?: string | null;
          id?: string;
          role: Database["public"]["Enums"]["app_role"];
          user_id: string;
        };
        Update: {
          created_at?: string;
          custom_label?: string | null;
          id?: string;
          role?: Database["public"]["Enums"]["app_role"];
          user_id?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"];
          _user_id: string;
        };
        Returns: boolean;
      };
    };
    Enums: {
      app_role: "admin" | "doctor" | "staff" | "custom";
      appointment_status: "scheduled" | "confirmed" | "completed" | "cancelled" | "no_show";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "doctor", "staff", "custom"],
      appointment_status: ["scheduled", "confirmed", "completed", "cancelled", "no_show"],
    },
  },
} as const;
