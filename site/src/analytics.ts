import type { PostHog } from "posthog-js/dist/module.slim.no-external";

/** Public project token for the "Headroom site" project in PostHog. Browser tokens are meant to be public. */
const token = "phc_AwXzW5cqmi6dZSnFM8Leak5kRH6DLS75jqZdgPBEhq9g";

/** Where a Download link sits on the page, so clicks can be compared by placement. */
export type DownloadPlacement = "nav" | "hero" | "footer";

/**
 * Counts page views and Download clicks, and nothing else: no cookies or local storage, no autocapture,
 * no session recording. Events go through /ingest on this domain (see vercel.json) so ad blockers
 * don't drop them. Only production builds load PostHog, as a separate chunk that doesn't hold up
 * rendering, and it uses the slim build without bundled extensions.
 */
const client: Promise<PostHog | undefined> = import.meta.env.PROD
  ? import("posthog-js/dist/module.slim.no-external").then(({ default: posthog }) => {
      posthog.init(token, {
        api_host: "/ingest",
        ui_host: "https://us.posthog.com",
        persistence: "memory",
        person_profiles: "never",
        autocapture: false,
        capture_pageview: true,
        capture_pageleave: false,
        rageclick: false,
        capture_heatmaps: false,
        capture_dead_clicks: false,
        capture_exceptions: false,
        disable_session_recording: true,
        disable_surveys: true,
        disable_product_tours: true,
        disable_conversations: true,
        disable_web_experiments: true,
        disable_external_dependency_loading: true,
        advanced_disable_flags: true,
      });
      return posthog;
    })
  : Promise.resolve(undefined);

export function trackDownload(placement: DownloadPlacement) {
  void client.then((posthog) => posthog?.capture("download_clicked", { placement }));
}
