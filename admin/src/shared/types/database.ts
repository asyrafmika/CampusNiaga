export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      app_config: {
        Row: {
          categories: string[]
          created_at: string
          id: boolean
          max_application_documents: number
          max_upload_bytes: number
          student_email_domains: string[]
          test_allowlist: string[]
          updated_at: string
        }
        Insert: {
          categories?: string[]
          created_at?: string
          id?: boolean
          max_application_documents?: number
          max_upload_bytes?: number
          student_email_domains?: string[]
          test_allowlist?: string[]
          updated_at?: string
        }
        Update: {
          categories?: string[]
          created_at?: string
          id?: boolean
          max_application_documents?: number
          max_upload_bytes?: number
          student_email_domains?: string[]
          test_allowlist?: string[]
          updated_at?: string
        }
        Relationships: []
      }
      application_status_history: {
        Row: {
          actor_id: string | null
          actor_role: string
          application_id: string
          created_at: string
          from_status: string
          id: number
          note: string | null
          to_status: string
        }
        Insert: {
          actor_id?: string | null
          actor_role: string
          application_id: string
          created_at?: string
          from_status: string
          id?: never
          note?: string | null
          to_status: string
        }
        Update: {
          actor_id?: string | null
          actor_role?: string
          application_id?: string
          created_at?: string
          from_status?: string
          id?: never
          note?: string | null
          to_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "application_status_history_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_status_history_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "business_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_logs: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          id: number
          metadata: Json
          target_id: string
          target_type: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          id?: never
          metadata?: Json
          target_id: string
          target_type: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          id?: never
          metadata?: Json
          target_id?: string
          target_type?: string
        }
        Relationships: []
      }
      business_applications: {
        Row: {
          applicant_id: string
          business_name: string
          category: string
          collection_details: string
          contact_details: string
          created_at: string
          decided_at: string | null
          description: string
          document_paths: string[]
          id: string
          remarks: string | null
          reviewer_id: string | null
          status: string
          submitted_at: string | null
          updated_at: string
        }
        Insert: {
          applicant_id?: string
          business_name?: string
          category?: string
          collection_details?: string
          contact_details?: string
          created_at?: string
          decided_at?: string | null
          description?: string
          document_paths?: string[]
          id?: string
          remarks?: string | null
          reviewer_id?: string | null
          status?: string
          submitted_at?: string | null
          updated_at?: string
        }
        Update: {
          applicant_id?: string
          business_name?: string
          category?: string
          collection_details?: string
          contact_details?: string
          created_at?: string
          decided_at?: string | null
          description?: string
          document_paths?: string[]
          id?: string
          remarks?: string | null
          reviewer_id?: string | null
          status?: string
          submitted_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "business_applications_applicant_id_fkey"
            columns: ["applicant_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "business_applications_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      businesses: {
        Row: {
          application_id: string
          created_at: string
          description: string
          id: string
          logo_path: string | null
          name: string
          owner_id: string
          pickup_details: string
          pickup_lat: number | null
          pickup_lng: number | null
          status: string
          updated_at: string
        }
        Insert: {
          application_id: string
          created_at?: string
          description?: string
          id?: string
          logo_path?: string | null
          name: string
          owner_id: string
          pickup_details: string
          pickup_lat?: number | null
          pickup_lng?: number | null
          status?: string
          updated_at?: string
        }
        Update: {
          application_id?: string
          created_at?: string
          description?: string
          id?: string
          logo_path?: string | null
          name?: string
          owner_id?: string
          pickup_details?: string
          pickup_lat?: number | null
          pickup_lng?: number | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "businesses_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "business_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "businesses_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      campaigns: {
        Row: {
          allocated_qty: number
          business_id: string
          capacity: number
          close_at: string
          created_at: string
          id: string
          listing_id: string
          per_order_limit: number | null
          pickup_details: string
          price_sen: number
          start_at: string
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          allocated_qty?: number
          business_id: string
          capacity: number
          close_at: string
          created_at?: string
          id?: string
          listing_id: string
          per_order_limit?: number | null
          pickup_details: string
          price_sen: number
          start_at: string
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          allocated_qty?: number
          business_id?: string
          capacity?: number
          close_at?: string
          created_at?: string
          id?: string
          listing_id?: string
          per_order_limit?: number | null
          pickup_details?: string
          price_sen?: number
          start_at?: string
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "campaigns_business_id_fkey"
            columns: ["business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaigns_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "listings"
            referencedColumns: ["id"]
          },
        ]
      }
      conversations: {
        Row: {
          buyer_id: string
          buyer_last_read_id: number
          closed_at: string | null
          closed_by: string | null
          created_at: string
          id: string
          last_message_at: string | null
          listing_id: string
          order_id: string | null
          reservation_id: string | null
          seller_id: string
          seller_last_read_id: number
          updated_at: string
        }
        Insert: {
          buyer_id: string
          buyer_last_read_id?: number
          closed_at?: string | null
          closed_by?: string | null
          created_at?: string
          id?: string
          last_message_at?: string | null
          listing_id: string
          order_id?: string | null
          reservation_id?: string | null
          seller_id: string
          seller_last_read_id?: number
          updated_at?: string
        }
        Update: {
          buyer_id?: string
          buyer_last_read_id?: number
          closed_at?: string | null
          closed_by?: string | null
          created_at?: string
          id?: string
          last_message_at?: string | null
          listing_id?: string
          order_id?: string | null
          reservation_id?: string | null
          seller_id?: string
          seller_last_read_id?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversations_buyer_id_fkey"
            columns: ["buyer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_closed_by_fkey"
            columns: ["closed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "listings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: true
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_reservation_id_fkey"
            columns: ["reservation_id"]
            isOneToOne: true
            referencedRelation: "reservations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_seller_id_fkey"
            columns: ["seller_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      deal_payments: {
        Row: {
          amount_sen: number
          business_id: string | null
          buyer_id: string
          created_at: string
          decided_at: string | null
          due_at: string
          id: string
          order_id: string | null
          proof_path: string | null
          reject_reason: string | null
          reservation_id: string | null
          seller_id: string
          status: string
          submitted_at: string | null
          updated_at: string
        }
        Insert: {
          amount_sen: number
          business_id?: string | null
          buyer_id: string
          created_at?: string
          decided_at?: string | null
          due_at: string
          id?: string
          order_id?: string | null
          proof_path?: string | null
          reject_reason?: string | null
          reservation_id?: string | null
          seller_id: string
          status?: string
          submitted_at?: string | null
          updated_at?: string
        }
        Update: {
          amount_sen?: number
          business_id?: string | null
          buyer_id?: string
          created_at?: string
          decided_at?: string | null
          due_at?: string
          id?: string
          order_id?: string | null
          proof_path?: string | null
          reject_reason?: string | null
          reservation_id?: string | null
          seller_id?: string
          status?: string
          submitted_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "deal_payments_business_id_fkey"
            columns: ["business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_payments_buyer_id_fkey"
            columns: ["buyer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_payments_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: true
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_payments_reservation_id_fkey"
            columns: ["reservation_id"]
            isOneToOne: true
            referencedRelation: "reservations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_payments_seller_id_fkey"
            columns: ["seller_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      discovery_synonyms: {
        Row: {
          canonical: string
          term: string
        }
        Insert: {
          canonical: string
          term: string
        }
        Update: {
          canonical?: string
          term?: string
        }
        Relationships: []
      }
      listings: {
        Row: {
          business_id: string | null
          category: string
          condition: string
          created_at: string
          description: string
          hidden: boolean
          id: string
          mode: string
          normalized_title: string
          owner_id: string
          photo_paths: string[]
          pickup_area: string
          pickup_lat: number | null
          pickup_lng: number | null
          price_sen: number
          search_vector: unknown
          status: string
          stock: number
          title: string
          updated_at: string
        }
        Insert: {
          business_id?: string | null
          category: string
          condition: string
          created_at?: string
          description?: string
          hidden?: boolean
          id?: string
          mode?: string
          normalized_title: string
          owner_id: string
          photo_paths?: string[]
          pickup_area: string
          pickup_lat?: number | null
          pickup_lng?: number | null
          price_sen: number
          search_vector?: unknown
          status?: string
          stock?: number
          title: string
          updated_at?: string
        }
        Update: {
          business_id?: string | null
          category?: string
          condition?: string
          created_at?: string
          description?: string
          hidden?: boolean
          id?: string
          mode?: string
          normalized_title?: string
          owner_id?: string
          photo_paths?: string[]
          pickup_area?: string
          pickup_lat?: number | null
          pickup_lng?: number | null
          price_sen?: number
          search_vector?: unknown
          status?: string
          stock?: number
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "listings_business_id_fkey"
            columns: ["business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "listings_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          body: string
          conversation_id: string
          created_at: string
          id: number
          sender_id: string
        }
        Insert: {
          body: string
          conversation_id: string
          created_at?: string
          id?: never
          sender_id: string
        }
        Update: {
          body?: string
          conversation_id?: string
          created_at?: string
          id?: never
          sender_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string
          created_at: string
          id: number
          read: boolean
          recipient_id: string
          target: string | null
          title: string
          type: string
        }
        Insert: {
          body?: string
          created_at?: string
          id?: never
          read?: boolean
          recipient_id: string
          target?: string | null
          title: string
          type: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: never
          read?: boolean
          recipient_id?: string
          target?: string | null
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      opportunities: {
        Row: {
          active_supply_count: number
          algo_version: string
          calculated_at: string
          category: string
          cluster_key: string
          distinct_seller_count: number
          head_term: string
          insufficient_data: boolean
          keywords: string[]
          last_interest_at: string
          median_listed_price_sen: number | null
          median_preferred_price_sen: number | null
          params: Json
          price_gap: boolean
          reasons: string[]
          request_ids: string[]
          score: number
          unique_interest_count: number
        }
        Insert: {
          active_supply_count: number
          algo_version: string
          calculated_at?: string
          category: string
          cluster_key: string
          distinct_seller_count: number
          head_term: string
          insufficient_data: boolean
          keywords?: string[]
          last_interest_at: string
          median_listed_price_sen?: number | null
          median_preferred_price_sen?: number | null
          params: Json
          price_gap: boolean
          reasons: string[]
          request_ids?: string[]
          score: number
          unique_interest_count: number
        }
        Update: {
          active_supply_count?: number
          algo_version?: string
          calculated_at?: string
          category?: string
          cluster_key?: string
          distinct_seller_count?: number
          head_term?: string
          insufficient_data?: boolean
          keywords?: string[]
          last_interest_at?: string
          median_listed_price_sen?: number | null
          median_preferred_price_sen?: number | null
          params?: Json
          price_gap?: boolean
          reasons?: string[]
          request_ids?: string[]
          score?: number
          unique_interest_count?: number
        }
        Relationships: []
      }
      orders: {
        Row: {
          business_id: string
          buyer_id: string
          buyer_note: string | null
          campaign_id: string | null
          cancelled_by: string | null
          collection_details: string
          completed_at: string | null
          cost_sen: number | null
          created_at: string
          id: string
          listing_id: string
          qty: number
          status: string
          total_sen: number
          unit_price_sen: number
          updated_at: string
        }
        Insert: {
          business_id: string
          buyer_id: string
          buyer_note?: string | null
          campaign_id?: string | null
          cancelled_by?: string | null
          collection_details: string
          completed_at?: string | null
          cost_sen?: number | null
          created_at?: string
          id?: string
          listing_id: string
          qty: number
          status?: string
          total_sen: number
          unit_price_sen: number
          updated_at?: string
        }
        Update: {
          business_id?: string
          buyer_id?: string
          buyer_note?: string | null
          campaign_id?: string | null
          cancelled_by?: string | null
          collection_details?: string
          completed_at?: string | null
          cost_sen?: number | null
          created_at?: string
          id?: string
          listing_id?: string
          qty?: number
          status?: string
          total_sen?: number
          unit_price_sen?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "orders_business_id_fkey"
            columns: ["business_id"]
            isOneToOne: false
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_buyer_id_fkey"
            columns: ["buyer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "listings"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_details: {
        Row: {
          account_name: string | null
          account_number: string | null
          bank_name: string | null
          business_id: string | null
          created_at: string
          id: string
          profile_id: string | null
          qr_path: string | null
          updated_at: string
        }
        Insert: {
          account_name?: string | null
          account_number?: string | null
          bank_name?: string | null
          business_id?: string | null
          created_at?: string
          id?: string
          profile_id?: string | null
          qr_path?: string | null
          updated_at?: string
        }
        Update: {
          account_name?: string | null
          account_number?: string | null
          bank_name?: string | null
          business_id?: string | null
          created_at?: string
          id?: string
          profile_id?: string | null
          qr_path?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_details_business_id_fkey"
            columns: ["business_id"]
            isOneToOne: true
            referencedRelation: "businesses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_details_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      product_requests: {
        Row: {
          campus_area: string
          category: string
          cluster_key: string
          created_at: string
          creator_id: string
          id: string
          name: string
          normalized_name: string
          notes: string | null
          preferred_price_sen: number | null
          status: string
          updated_at: string
        }
        Insert: {
          campus_area: string
          category: string
          cluster_key: string
          created_at?: string
          creator_id: string
          id?: string
          name: string
          normalized_name: string
          notes?: string | null
          preferred_price_sen?: number | null
          status?: string
          updated_at?: string
        }
        Update: {
          campus_area?: string
          category?: string
          cluster_key?: string
          created_at?: string
          creator_id?: string
          id?: string
          name?: string
          normalized_name?: string
          notes?: string | null
          preferred_price_sen?: number | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_requests_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          account_status: string
          created_at: string
          email: string
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          account_status?: string
          created_at?: string
          email: string
          id: string
          name: string
          updated_at?: string
        }
        Update: {
          account_status?: string
          created_at?: string
          email?: string
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      reports: {
        Row: {
          action: string | null
          conversation_id: string | null
          created_at: string
          details: string
          id: string
          listing_id: string | null
          reason: string
          reported_user_id: string | null
          reporter_id: string
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          action?: string | null
          conversation_id?: string | null
          created_at?: string
          details?: string
          id?: string
          listing_id?: string | null
          reason: string
          reported_user_id?: string | null
          reporter_id: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          action?: string | null
          conversation_id?: string | null
          created_at?: string
          details?: string
          id?: string
          listing_id?: string | null
          reason?: string
          reported_user_id?: string | null
          reporter_id?: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "reports_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "listings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reported_user_id_fkey"
            columns: ["reported_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      request_interests: {
        Row: {
          created_at: string
          request_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          request_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          request_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_interests_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "product_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_interests_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      reservations: {
        Row: {
          buyer_id: string
          created_at: string
          expires_at: string | null
          id: string
          listing_id: string
          pickup_note: string | null
          qty: number
          seller_id: string
          status: string
          updated_at: string
        }
        Insert: {
          buyer_id: string
          created_at?: string
          expires_at?: string | null
          id?: string
          listing_id: string
          pickup_note?: string | null
          qty: number
          seller_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          buyer_id?: string
          created_at?: string
          expires_at?: string | null
          id?: string
          listing_id?: string
          pickup_note?: string | null
          qty?: number
          seller_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "reservations_buyer_id_fkey"
            columns: ["buyer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reservations_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "listings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reservations_seller_id_fkey"
            columns: ["seller_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      staff_roles: {
        Row: {
          created_at: string
          granted_by: string | null
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          granted_by?: string | null
          role: string
          user_id: string
        }
        Update: {
          created_at?: string
          granted_by?: string | null
          role?: string
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      application_status_summary: {
        Args: never
        Returns: {
          status: string
          total: number
        }[]
      }
      business_dashboard: {
        Args: { from_at?: string; to_at?: string }
        Returns: Json
      }
      can_delete_application_document: {
        Args: { object_name: string }
        Returns: boolean
      }
      can_delete_payment_proof: {
        Args: { object_name: string }
        Returns: boolean
      }
      can_read_application_document: {
        Args: { object_name: string }
        Returns: boolean
      }
      can_read_payment_proof: {
        Args: { object_name: string }
        Returns: boolean
      }
      can_read_payment_qr: { Args: { object_name: string }; Returns: boolean }
      can_upload_application_document: {
        Args: { object_name: string }
        Returns: boolean
      }
      can_upload_business_logo: {
        Args: { object_name: string }
        Returns: boolean
      }
      can_upload_listing_photo: {
        Args: { object_name: string }
        Returns: boolean
      }
      can_upload_payment_proof: {
        Args: { object_name: string }
        Returns: boolean
      }
      cancel_order_hold: {
        Args: { by_whom: string; target_order: string }
        Returns: undefined
      }
      close_conversation: { Args: { conversation_id: string }; Returns: Json }
      close_product_request: { Args: { request_id: string }; Returns: Json }
      conversation_can_send: {
        Args: { c: Database["public"]["Tables"]["conversations"]["Row"] }
        Returns: boolean
      }
      conversation_cards: {
        Args: { uid: string }
        Returns: Database["public"]["CompositeTypes"]["conversation_card"][]
        SetofOptions: {
          from: "*"
          to: "conversation_card"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      create_product_request: {
        Args: {
          campus_area: string
          category: string
          name: string
          notes?: string
          preferred_price_sen?: number
        }
        Returns: Json
      }
      discovery_cluster_key: {
        Args: { category: string; name: string }
        Returns: string
      }
      discovery_params: { Args: never; Returns: Json }
      discovery_rm: { Args: { sen: number }; Returns: string }
      discovery_singular: { Args: { word: string }; Returns: string }
      discovery_stop_words: { Args: never; Returns: string[] }
      discovery_terms: { Args: { value: string }; Returns: string[] }
      dismiss_report: {
        Args: { note?: string; report_id: string }
        Returns: Json
      }
      expire_listing_reservations: {
        Args: { target_listing: string }
        Returns: number
      }
      expire_overdue_payments: { Args: never; Returns: number }
      expire_unpaid_orders: {
        Args: { target_campaign: string; target_listing: string }
        Returns: number
      }
      get_conversation: {
        Args: { conversation_id: string }
        Returns: Database["public"]["CompositeTypes"]["conversation_card"]
        SetofOptions: {
          from: "*"
          to: "conversation_card"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      get_listing: {
        Args: { listing_id: string }
        Returns: Database["public"]["CompositeTypes"]["listing_card"][]
        SetofOptions: {
          from: "*"
          to: "listing_card"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      get_my_access: { Args: never; Returns: Json }
      get_my_business: { Args: never; Returns: Json }
      get_payment: { Args: { payment_id: string }; Returns: Json }
      get_reported_conversation: { Args: { report_id: string }; Returns: Json }
      get_storefront: { Args: { business_id: string }; Returns: Json }
      is_admin: { Args: never; Returns: boolean }
      is_eligible_student_email: {
        Args: { allowlist: string[]; domains: string[]; email: string }
        Returns: boolean
      }
      is_reviewer: { Args: never; Returns: boolean }
      is_staff: { Args: never; Returns: boolean }
      is_student: { Args: never; Returns: boolean }
      list_product_requests: {
        Args: {
          category?: string
          cluster_key?: string
          mine?: boolean
          page_offset?: number
          page_size?: number
        }
        Returns: Database["public"]["CompositeTypes"]["request_card"][]
        SetofOptions: {
          from: "*"
          to: "request_card"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      listing_categories: { Args: never; Returns: string[] }
      lock_payment: {
        Args: { target_payment: string }
        Returns: {
          amount_sen: number
          business_id: string | null
          buyer_id: string
          created_at: string
          decided_at: string | null
          due_at: string
          id: string
          order_id: string | null
          proof_path: string | null
          reject_reason: string | null
          reservation_id: string | null
          seller_id: string
          status: string
          submitted_at: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "deal_payments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mark_conversation_read: {
        Args: { conversation_id: string }
        Returns: Json
      }
      moderate_listing: {
        Args: { hide: boolean; listing_id: string; note?: string }
        Returns: Json
      }
      my_conversations: {
        Args: { page_offset?: number; page_size?: number }
        Returns: Database["public"]["CompositeTypes"]["conversation_card"][]
        SetofOptions: {
          from: "*"
          to: "conversation_card"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      my_orders: {
        Args: { page_offset?: number; page_size?: number; side?: string }
        Returns: Database["public"]["CompositeTypes"]["order_card"][]
        SetofOptions: {
          from: "*"
          to: "order_card"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      my_reservations: {
        Args: { side?: string }
        Returns: Database["public"]["CompositeTypes"]["reservation_card"][]
        SetofOptions: {
          from: "*"
          to: "reservation_card"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      normalize_text: { Args: { value: string }; Returns: string }
      notify: {
        Args: {
          body: string
          kind: string
          recipient: string
          target: string
          title: string
        }
        Returns: undefined
      }
      open_conversation: {
        Args: { order_id?: string; reservation_id?: string }
        Returns: Json
      }
      owns_business: { Args: { business_id: string }; Returns: boolean }
      participant_conversation: {
        Args: { conversation_id: string; lock_row: boolean }
        Returns: {
          buyer_id: string
          buyer_last_read_id: number
          closed_at: string | null
          closed_by: string | null
          created_at: string
          id: string
          last_message_at: string | null
          listing_id: string
          order_id: string | null
          reservation_id: string | null
          seller_id: string
          seller_last_read_id: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "conversations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      payment_details_for: {
        Args: { business: string; seller: string }
        Returns: {
          account_name: string | null
          account_number: string | null
          bank_name: string | null
          business_id: string | null
          created_at: string
          id: string
          profile_id: string | null
          qr_path: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "payment_details"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      pickup_pin_problem: {
        Args: { lat: number; lng: number }
        Returns: string
      }
      place_order: {
        Args: {
          buyer_note?: string
          campaign_id?: string
          listing_id: string
          payment_method?: string
          qty?: number
        }
        Returns: Json
      }
      raise_app_error: {
        Args: { message: string; reason: string }
        Returns: undefined
      }
      recompute_opportunities: {
        Args: { target_cluster?: string }
        Returns: number
      }
      recompute_opportunity: {
        Args: { target_cluster: string }
        Returns: undefined
      }
      report_conversation: {
        Args: { conversation_id: string; details?: string; reason: string }
        Returns: Json
      }
      report_listing: {
        Args: { details?: string; listing_id: string; reason: string }
        Returns: Json
      }
      request_reservation: {
        Args: {
          listing_id: string
          payment_method?: string
          pickup_note?: string
          qty?: number
        }
        Returns: Json
      }
      resolve_reservation: {
        Args: { action: string; reservation_id: string }
        Returns: Json
      }
      review_business_application: {
        Args: { action: string; application_id: string; note?: string }
        Returns: Json
      }
      review_payment: {
        Args: { accept: boolean; payment_id: string; reason?: string }
        Returns: Json
      }
      search_listings: {
        Args: {
          category?: string
          condition?: string
          max_price_sen?: number
          min_price_sen?: number
          page_offset?: number
          page_size?: number
          search?: string
          sort?: string
        }
        Returns: Database["public"]["CompositeTypes"]["listing_card"][]
        SetofOptions: {
          from: "*"
          to: "listing_card"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      seller_accepts_transfer: {
        Args: { listing_id: string }
        Returns: boolean
      }
      send_message: {
        Args: { body: string; conversation_id: string }
        Returns: Json
      }
      set_account_status: {
        Args: { account_status: string; note?: string; user_id: string }
        Returns: Json
      }
      set_business_status: {
        Args: { business_id: string; note?: string; status: string }
        Returns: Json
      }
      set_campaign_status: {
        Args: { campaign_id: string; new_status: string }
        Returns: Json
      }
      set_listing_status: {
        Args: { listing_id: string; new_status: string }
        Returns: Json
      }
      set_order_cost: {
        Args: { cost_sen: number; order_id: string }
        Returns: Json
      }
      set_payment_details: {
        Args: {
          account_name?: string
          account_number?: string
          bank_name?: string
          for_business: boolean
          qr_path?: string
        }
        Returns: Json
      }
      set_staff_role: {
        Args: { enabled: boolean; role: string; target_user_id: string }
        Returns: Json
      }
      submit_business_application: {
        Args: { application_id: string; response_note?: string }
        Returns: Json
      }
      submit_payment_proof: {
        Args: { payment_id: string; proof_path: string }
        Returns: Json
      }
      toggle_request_interest: { Args: { request_id: string }; Returns: Json }
      transition_order: {
        Args: { action: string; order_id: string }
        Returns: Json
      }
      update_storefront: {
        Args: {
          description: string
          logo_path?: string
          pickup_details: string
          pickup_lat?: number
          pickup_lng?: number
        }
        Returns: Json
      }
      upsert_campaign: {
        Args: {
          campaign_id: string
          capacity: number
          close_at: string
          listing_id: string
          per_order_limit: number
          pickup_details: string
          price_sen: number
          start_at: string
          title: string
        }
        Returns: Json
      }
      upsert_listing: {
        Args: {
          category: string
          condition: string
          description: string
          listing_id: string
          mode?: string
          photo_paths: string[]
          pickup_area: string
          pickup_lat?: number
          pickup_lng?: number
          price_sen: number
          quantity: number
          title: string
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      conversation_card: {
        conversation_id: string | null
        kind: string | null
        reservation_id: string | null
        order_id: string | null
        listing_id: string | null
        listing_title: string | null
        listing_photo: string | null
        other_party_name: string | null
        i_am_buyer: boolean | null
        last_message: string | null
        last_message_at: string | null
        last_message_mine: boolean | null
        unread_count: number | null
        can_send: boolean | null
        closed: boolean | null
        created_at: string | null
      }
      listing_card: {
        id: string | null
        owner_id: string | null
        seller_name: string | null
        mode: string | null
        title: string | null
        description: string | null
        category: string | null
        price_sen: number | null
        condition: string | null
        photo_paths: string[] | null
        stock: number | null
        pickup_area: string | null
        status: string | null
        created_at: string | null
        business_id: string | null
        business_name: string | null
        pickup_lat: number | null
        pickup_lng: number | null
      }
      order_card: {
        id: string | null
        listing_id: string | null
        listing_title: string | null
        listing_photo: string | null
        business_id: string | null
        business_name: string | null
        campaign_id: string | null
        campaign_title: string | null
        qty: number | null
        unit_price_sen: number | null
        total_sen: number | null
        status: string | null
        buyer_note: string | null
        collection_details: string | null
        cancelled_by: string | null
        created_at: string | null
        updated_at: string | null
        completed_at: string | null
        i_am_buyer: boolean | null
        other_party_name: string | null
        other_party_email: string | null
        cost_sen: number | null
        payment_id: string | null
        payment_status: string | null
        payment_due_at: string | null
        payment_reject_reason: string | null
      }
      request_card: {
        id: string | null
        name: string | null
        category: string | null
        preferred_price_sen: number | null
        campus_area: string | null
        notes: string | null
        status: string | null
        cluster_key: string | null
        created_at: string | null
        interest_count: number | null
        i_am_interested: boolean | null
        is_mine: boolean | null
      }
      reservation_card: {
        id: string | null
        listing_id: string | null
        listing_title: string | null
        listing_photo: string | null
        pickup_area: string | null
        price_sen: number | null
        qty: number | null
        pickup_note: string | null
        status: string | null
        expires_at: string | null
        created_at: string | null
        updated_at: string | null
        i_am_buyer: boolean | null
        other_party_name: string | null
        other_party_email: string | null
        payment_id: string | null
        payment_status: string | null
        payment_due_at: string | null
        payment_reject_reason: string | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
