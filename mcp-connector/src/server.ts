import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { UnifyClient } from "./client.js";
import { loadConfig } from "./config.js";
import { registerTools } from "./tools.js";

export const VERSION = "1.1.0";

export interface BuildOptions {
  readOnly: boolean;
  timeZone: string;
}

/** Builds an MCP server whose tools act through `client` (one signed-in Unify user). */
export function buildServer(client: UnifyClient, config: BuildOptions) {
  const server = new McpServer(
    { name: "unify", title: "Unify Booking Platform", version: VERSION },
    {
      instructions: [
        "Unify is a multi-tenant booking platform for small businesses (clinics, restaurants, gyms, schools/tuition,",
        "real estate, tourism operators, general services). These tools act as the signed-in Unify user, inside",
        "that user's business only.",
        "",
        "Key concepts: a Resource is the bookable thing (doctor, table, trainer, boat, room, vehicle). A Booking Type",
        "is the service sold (Consultation, Whale Watching Tour, Room Stay) and has a booking unit: Slot (fixed time",
        "slots), Night (check-in/out), DateRange (multi-day rental) or Package (date range + itinerary).",
        "",
        "Workflow tips:",
        "- unify_whoami gives the business type, the user's role and today's date in business time.",
        `- Times without an offset are read as business-local time (${config.timeZone}). Every timestamp returned`,
        "  gets a matching ...Local field - quote those to the user, not the raw UTC values.",
        "- Resource and booking-type ids come from unify_list_resources / unify_list_booking_types; free times from",
        "  unify_find_available_slots (Slot) or unify_get_booked_ranges (Night/DateRange).",
        "- Cancelling a booking notifies the customer; applying an AI workflow creates bookings.",
        "- unify_api_get reads endpoints that no dedicated tool covers.",
        config.readOnly ? "- This connector is in READ-ONLY mode: write tools are disabled." : "",
      ].join("\n"),
    },
  );

  registerTools(server, client, { readOnly: config.readOnly });

  server.registerPrompt(
    "daily_briefing",
    {
      title: "Daily business briefing",
      description: "Summarise today's bookings, alerts, conflicts and pending approvals for the business.",
      argsSchema: { date: z.string().optional().describe("YYYY-MM-DD, default today") },
    },
    ({ date }) => ({
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text:
              `Give me a briefing for my Unify business for ${date ?? "today"}. Use unify_whoami first, then ` +
              "list that day's bookings, check the operations dashboard alerts for my business type, look for " +
              "double-bookings, pending AI workflows and unread notifications. Finish with a short list of things " +
              "I should act on. Show times in business-local time.",
          },
        },
      ],
    }),
  );

  server.registerPrompt(
    "book_appointment",
    {
      title: "Book an appointment",
      description: "Walk through finding a free slot and booking it for a customer.",
      argsSchema: { request: z.string().describe("e.g. 'Dental check-up for Nimal Perera next Tuesday morning'") },
    },
    ({ request }) => ({
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text:
              `Book this in Unify: ${request}\n\nFind the right booking type and resource, look up the customer, ` +
              "find free slots, propose the best options to me, and only create the booking after I confirm.",
          },
        },
      ],
    }),
  );

  return server;
}

export function createServer(config = loadConfig(), fetchImpl?: typeof fetch) {
  const client = new UnifyClient(config, fetchImpl);
  return { server: buildServer(client, config), client };
}

