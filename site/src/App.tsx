import type { ReactNode } from "react";
import { Shot, type ShotName } from "./Shot";
import { trackDownload, type DownloadPlacement } from "./analytics";

const download = { href: "/Headroom.dmg", note: "macOS 14 or later · Apple silicon and Intel · 1.9 MB" };

export function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Steps />
        <MenuBar />
        <HandsOff />
        <FinePrint />
        <Faq />
      </main>
      <Footer />
    </>
  );
}

/* Shared pieces */

function Container({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`mx-auto w-full max-w-6xl px-5 sm:px-8 ${className}`}>{children}</div>;
}

function Section({ id, children, tone = "plain" }: { id: string; children: ReactNode; tone?: "plain" | "tint" }) {
  const bg = tone === "tint" ? "bg-paper-2 dark:bg-paper-2-dark" : "";
  return (
    <section id={id} className={`border-t border-line py-20 sm:py-24 dark:border-line-dark ${bg}`}>
      <Container>{children}</Container>
    </section>
  );
}

/** Section title with a mono label on the left, like a line in a ledger. */
function Heading({ label, title, lead }: { label: string; title: string; lead?: string }) {
  return (
    <div className="grid gap-3 lg:grid-cols-12">
      <p className="font-mono text-xs tracking-wider text-ink-muted uppercase lg:col-span-4 lg:pt-3 dark:text-ink-muted-dark">
        {label}
      </p>
      <div className="lg:col-span-8">
        <h2 className="text-3xl font-semibold tracking-tight text-balance sm:text-4xl">{title}</h2>
        {lead && <p className="mt-4 max-w-2xl text-lg text-ink-muted dark:text-ink-muted-dark">{lead}</p>}
      </div>
    </div>
  );
}

function DownloadButton({ placement }: { placement: DownloadPlacement }) {
  return (
    <a
      href={download.href}
      download
      onClick={() => trackDownload(placement)}
      className="inline-flex items-center gap-2 rounded-lg bg-accent px-5 py-3 font-semibold text-white hover:bg-accent-strong"
    >
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true">
        <path d="M8 2v8m0 0 3-3M8 10 5 7M3 13h10" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      Download for Mac
    </a>
  );
}

/** The five labels every item gets in the app, with the app's colors. */
const tags = {
  rebuilds: { label: "Rebuildable", className: "text-green-700 bg-green-600/10 dark:text-green-400" },
  redownload: { label: "Redownload", className: "text-blue-700 bg-blue-600/10 dark:text-blue-400" },
  leftover: { label: "Leftover", className: "text-orange-700 bg-orange-600/10 dark:text-orange-400" },
  personal: { label: "Personal data", className: "text-red-700 bg-red-600/10 dark:text-red-400" },
  managed: { label: "App-managed", className: "text-ink-muted bg-ink-muted/10 dark:text-ink-muted-dark" },
} as const;

type Tag = keyof typeof tags;

function TagPill({ tag }: { tag: Tag }) {
  const { label, className } = tags[tag];
  return <span className={`rounded px-1.5 py-0.5 font-sans text-[11px] font-medium whitespace-nowrap ${className}`}>{label}</span>;
}

/* Sections */

function Nav() {
  const links = [
    ["#how", "How it works"],
    ["#hands-off", "What it won't touch"],
    ["#fine-print", "Fine print"],
    ["#faq", "FAQ"],
  ] as const;
  return (
    <header className="sticky top-0 z-10 border-b border-line bg-paper/85 backdrop-blur dark:border-line-dark dark:bg-paper-dark/85">
      <Container className="flex h-14 items-center justify-between">
        <a href="#top" className="flex items-center gap-2.5 font-semibold">
          <img src="/icon-512.png" alt="" width="26" height="26" />
          Headroom
        </a>
        <nav className="hidden gap-6 text-sm text-ink-muted md:flex dark:text-ink-muted-dark">
          {links.map(([href, label]) => (
            <a key={href} href={href} className="hover:text-ink dark:hover:text-ink-dark">
              {label}
            </a>
          ))}
        </nav>
        <a href={download.href} download onClick={() => trackDownload("nav")} className="text-sm font-semibold text-accent hover:underline dark:text-accent-bright">
          Download
        </a>
      </Container>
    </header>
  );
}

/** A sample of lines from the app's example scan, not its ten largest. */
const receipt: [string, number, Tag][] = [
  ["Sam's iPhone 16 backup", 63.2, "personal"],
  ["Photos library", 61.3, "managed"],
  ["Sam's iPhone 11 backup", 41.8, "personal"],
  ["Xcode build data", 38.4, "rebuilds"],
  ["Docker disk image", 32.0, "managed"],
  ["Device support files", 21.7, "redownload"],
  ["Ollama models", 14.5, "redownload"],
  ["npm cache", 9.8, "rebuilds"],
  ["raytracer/target", 5.4, "rebuilds"],
  ["com.adobe.Premiere", 4.4, "leftover"],
];

const gigabytes = (lines: typeof receipt) => lines.reduce((sum, [, size]) => sum + size, 0).toFixed(1);

function Hero() {
  const recoverable = receipt.filter(([, , tag]) => tag === "rebuilds" || tag === "redownload" || tag === "leftover");
  return (
    <section id="top" className="pt-14 pb-20 sm:pt-20">
      <Container className="grid items-center gap-12 lg:grid-cols-12">
        <div className="lg:col-span-6">
          <p className="font-mono text-xs tracking-wider text-ink-muted uppercase dark:text-ink-muted-dark">
            Free · Offline · No account
          </p>
          <h1 className="mt-4 text-5xl font-semibold tracking-tight sm:text-6xl">System Data, itemized.</h1>
          <p className="mt-6 max-w-xl text-lg text-ink-muted sm:text-xl dark:text-ink-muted-dark">
            Storage settings gives you one grey bar. Headroom lists what's in it, tells you what clearing each item would
            cost you, and moves only what you pick to the Trash.
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-x-5 gap-y-3">
            <DownloadButton placement="hero" />
            <a href="#how" className="text-sm font-medium text-ink-muted hover:text-ink dark:text-ink-muted-dark dark:hover:text-ink-dark">
              How it works ↓
            </a>
          </div>
          <p className="mt-4 text-sm text-balance text-ink-muted dark:text-ink-muted-dark">{download.note}</p>
        </div>
        <div className="lg:col-span-6">
          <div className="rounded-lg border border-line bg-paper-2 p-5 font-mono text-[13px] shadow-[0_24px_50px_-30px_rgba(60,40,10,0.35)] sm:p-7 dark:border-line-dark dark:bg-paper-2-dark dark:shadow-none">
            <div className="flex justify-between text-xs text-ink-muted uppercase dark:text-ink-muted-dark">
              <span>Scan · Sam's MacBook</span>
              <span>494 GB disk</span>
            </div>
            <ul className="mt-4 space-y-2 border-y border-dashed border-line py-4 dark:border-line-dark">
              {receipt.map(([name, size, tag]) => (
                <li key={name} className="flex items-baseline gap-2">
                  <span className="truncate">{name}</span>
                  <span className="hidden sm:inline">
                    <TagPill tag={tag} />
                  </span>
                  <span className="min-w-4 flex-1 border-b border-dotted border-ink-muted/40 dark:border-ink-muted-dark/40" />
                  <span className="tabular-nums">{size.toFixed(1)} GB</span>
                </li>
              ))}
              <li className="text-ink-muted dark:text-ink-muted-dark">+ 21 more</li>
            </ul>
            <div className="mt-4 flex justify-between">
              <span>Listed</span>
              <span className="tabular-nums">{gigabytes(receipt)} GB</span>
            </div>
            <div className="mt-1 flex justify-between font-semibold text-accent dark:text-accent-bright">
              <span>Comes back if you clear it</span>
              <span className="tabular-nums">{gigabytes(recoverable)} GB</span>
            </div>
          </div>
          <p className="mt-3 text-center text-xs text-ink-muted dark:text-ink-muted-dark">
            A sample from the example scan built into the app. Yours will look different.
          </p>
        </div>
      </Container>
    </section>
  );
}

type Step = { title: string; body: ReactNode; shot: ShotName; alt: string; narrow?: boolean };

const steps: Step[] = [
  {
    title: "Scan",
    body: "About a minute. Headroom checks around 35 places that developer tools, browsers and chat apps fill up. Then it looks for per-app caches, iPhone backups, old installers, deleted-app leftovers, and build folders in your code folders.",
    shot: "overview",
    alt: "Headroom's overview: a disk bar, a fill estimate, three items worth a look, and a grid of squares colored by category.",
  },
  {
    title: "Read the label",
    body: (
      <>
        <span>Every item says what it is, which app made it, and what happens if it goes:</span>
        <span className="mt-3 flex flex-wrap gap-1.5">
          {(Object.keys(tags) as Tag[]).map((tag) => (
            <TagPill key={tag} tag={tag} />
          ))}
        </span>
      </>
    ),
    shot: "category-expanded",
    alt: "The Developer tools list with Xcode build data expanded to show its explanation and path.",
  },
  {
    title: "Pick",
    body: "Nothing starts ticked. Build folders only count when the project's own files confirm them, such as package.json next to node_modules, and each shows when you last worked on it. Select untouched ticks every project nobody has changed in 90 days.",
    shot: "projects",
    alt: "The Project build folders list with four untouched projects checked and a Select untouched button.",
  },
  {
    title: "Check the plan",
    body: "The plan groups your picks by what you'd lose and lists warnings, such as a backup that may be a device's only copy. Right before each move, Headroom checks the item again and skips it if its app is open.",
    shot: "review",
    alt: "The cleanup plan grouped into Rebuildable, Can be downloaded again and Personal data, with a warning about app archives.",
    narrow: true,
  },
  {
    title: "Change your mind",
    body: "Everything goes to the Trash, not into the void. The Trash tab lists what moved and puts any item back in one click, until you empty the Trash.",
    shot: "trash",
    alt: "Headroom's Trash tab listing moved items with a Put Back button on each.",
  },
];

function Steps() {
  return (
    <Section id="how" tone="tint">
      <Heading label="How it works" title="Five steps, and you make every call" />
      <ol className="mt-14 space-y-20 sm:space-y-24">
        {steps.map((step, index) => (
          <li key={step.title} className="grid gap-6 lg:grid-cols-12 lg:gap-12">
            <div className="lg:sticky lg:top-24 lg:col-span-4 lg:self-start">
              <p className="font-mono text-sm text-accent dark:text-accent-bright">{String(index + 1).padStart(2, "0")}</p>
              <h3 className="mt-1 text-2xl font-semibold tracking-tight">{step.title}</h3>
              <p className="mt-3 flex flex-col text-ink-muted dark:text-ink-muted-dark">{step.body}</p>
            </div>
            <div className={`lg:col-span-8 ${step.narrow ? "flex justify-center" : ""}`}>
              <Shot name={step.shot} alt={step.alt} className={step.narrow ? "shot w-full max-w-lg" : "shot w-full"} />
            </div>
          </li>
        ))}
      </ol>
    </Section>
  );
}

function MenuBar() {
  const lines: [string, string][] = [
    ["Fill estimate", "Headroom fits a trend through your recent scans to guess roughly when the disk fills if nothing changes."],
    ["Worth a look", "Sources that grew since last time and projects gone untouched, each one click away."],
    ["Weekly check", "An optional background scan. Off until you turn it on."],
    ["Low space alert", "A notification when free space drops under 10%."],
  ];
  return (
    <Section id="menubar">
      <Heading label="Between scans" title="It watches free space from the menu bar" />
      <div className="mt-10 grid items-center gap-12 lg:grid-cols-12">
        <dl className="grid gap-x-8 gap-y-6 sm:grid-cols-2 lg:col-span-4 lg:col-start-5 lg:grid-cols-1">
          {lines.map(([term, detail]) => (
            <div key={term}>
              <dt className="font-semibold">{term}</dt>
              <dd className="mt-1 text-ink-muted dark:text-ink-muted-dark">{detail}</dd>
            </div>
          ))}
        </dl>
        <div className="flex justify-center lg:col-span-4">
          <Shot name="menubar" alt="The menu bar panel: 27.2 GB free of 494 GB, a fill estimate, three items worth a look, and toggles for the weekly check and low space alert." className="shot w-full max-w-sm" />
        </div>
      </div>
    </Section>
  );
}

function HandsOff() {
  const items: [string, string][] = [
    ["Photos library", "Photos"],
    ["Mail downloads", "Mail"],
    ["Messages attachments", "Messages"],
    ["iCloud Drive", "iCloud"],
    ["Docker disk image", "Docker"],
    ["Simulator devices", "Simulator"],
  ];
  return (
    <Section id="hands-off" tone="tint">
      <Heading
        label="What it won't touch"
        title="Some things only their own app should delete"
        lead="Headroom shows how big these are, then points you to the setting that shrinks them. You can't tick them, so they can't end up in the Trash by accident."
      />
      <ul className="mt-10 grid gap-px overflow-hidden rounded-lg border border-line bg-line sm:grid-cols-2 lg:ml-[calc(4/12*100%)] lg:grid-cols-3 dark:border-line-dark dark:bg-line-dark">
        {items.map(([name, owner]) => (
          <li key={name} className="bg-paper px-5 py-4 dark:bg-paper-dark">
            <span className="font-medium">{name}</span>
            <span className="block text-sm text-ink-muted dark:text-ink-muted-dark">Managed by {owner}</span>
          </li>
        ))}
      </ul>
    </Section>
  );
}

function FinePrint() {
  const rows: [string, string][] = [
    ["Price", "Free. No license key, no subscription, and it runs on as many Macs as you like."],
    ["Network", "None. No update check, no license check, no crash reports. A firewall will show nothing."],
    ["Account and analytics", "The app has neither. It keeps three small JSON files in Application Support: the last scan, scan history and the Trash log."],
    ["This website", "Counts visits and Download clicks with PostHog. No cookies, no session recording, and IP addresses are dropped. The app itself sends nothing."],
    ["What it reads", "File names, sizes and dates. It never opens your documents, photos or messages."],
    ["Full Disk Access", "Optional. Without it, Headroom skips Mail, Messages, device backups, app containers, and your Documents, Desktop and Downloads folders, and lists what it couldn't read."],
    ["Signing", "Signed with an Apple Developer ID and notarized by Apple, so macOS opens it without a warning."],
    ["Source", "Open source under the MIT license, on GitHub at fireboltdude1357/headroom."],
    ["Extras", "Example data mode to try everything without touching your disk, and CSV export of any scan (⌘E)."],
  ];
  return (
    <Section id="fine-print">
      <Heading label="Fine print" title="The short version: free, and it stays on your Mac" />
      <dl className="mt-10 divide-y divide-line border-y border-line lg:ml-[calc(4/12*100%)] dark:divide-line-dark dark:border-line-dark">
        {rows.map(([term, detail]) => (
          <div key={term} className="grid gap-1 py-4 sm:grid-cols-3 sm:gap-6">
            <dt className="font-mono text-sm text-ink-muted sm:pt-0.5 dark:text-ink-muted-dark">{term}</dt>
            <dd className="sm:col-span-2">{detail}</dd>
          </div>
        ))}
      </dl>
    </Section>
  );
}

const faq: [string, string][] = [
  [
    "How do I install it?",
    "Open the .dmg and drag Headroom to Applications. There's no installer. Its data lives in Application Support, plus its preferences.",
  ],
  [
    "Could it delete something important?",
    "Only items you tick go to the Trash, and nothing is ticked for you. App-managed items can't be ticked at all. Right before each move, Headroom checks the item again and skips it if its app is open or the file that identified it is gone.",
  ],
  [
    "Why don't the numbers match Storage settings?",
    "Headroom measures allocated file sizes itself and groups them by source rather than by Apple's categories. macOS also counts local snapshots and purgeable space differently. A file hard-linked inside one folder counts once, but links shared between folders and APFS clones count in each place, which is why cleanup reports space as \"up to\" what you'll get back.",
  ],
  [
    "When does the space come back?",
    "When you empty the Trash. Until then you can put anything back from the Trash tab.",
  ],
  [
    "What about files iCloud has offloaded?",
    "Headroom skips them. They take no space on your Mac, and it never downloads anything from iCloud to measure it.",
  ],
  [
    "Does it run in the background?",
    "While Headroom is open, the low space alert checks free space once an hour. Full scans only run in the background if you turn on the weekly check, which also registers Headroom as a login item. You can turn both off in Settings or the menu bar panel.",
  ],
  [
    "Which Macs does it run on?",
    "Any Mac with macOS 14 Sonoma or later, Apple silicon or Intel. The download is a universal build.",
  ],
];

function Faq() {
  return (
    <Section id="faq" tone="tint">
      <Heading label="FAQ" title="Questions" />
      <div className="mt-10 divide-y divide-line border-y border-line lg:ml-[calc(4/12*100%)] dark:divide-line-dark dark:border-line-dark">
        {faq.map(([question, answer]) => (
          <details key={question} className="group py-4">
            <summary className="flex cursor-pointer items-baseline gap-4 font-medium">
              <span aria-hidden="true" className="w-4 shrink-0 font-mono text-accent group-open:hidden dark:text-accent-bright">+</span>
              <span aria-hidden="true" className="hidden w-4 shrink-0 font-mono text-accent group-open:inline dark:text-accent-bright">−</span>
              {question}
            </summary>
            <p className="mt-2 pl-8 text-ink-muted dark:text-ink-muted-dark">{answer}</p>
          </details>
        ))}
      </div>
    </Section>
  );
}

function Footer() {
  return (
    <footer className="border-t border-line bg-paper-3 py-14 dark:border-line-dark dark:bg-paper-3-dark">
      <Container className="flex flex-col gap-8 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="flex items-center gap-2.5 text-lg font-semibold">
            <img src="/icon-512.png" alt="" width="28" height="28" />
            Headroom
          </p>
          <p className="mt-2 max-w-sm text-sm text-ink-muted dark:text-ink-muted-dark">
            A disk analyzer that explains itself. Made by{" "}
            <a href="https://architechsolutions.net" className="underline hover:text-ink dark:hover:text-ink-dark">
              Architech Solutions
            </a>
            . Open source on{" "}
            <a href="https://github.com/fireboltdude1357/headroom" className="underline hover:text-ink dark:hover:text-ink-dark">
              GitHub
            </a>
            .
          </p>
        </div>
        <div className="sm:text-right">
          <DownloadButton placement="footer" />
          <p className="mt-3 text-sm text-ink-muted dark:text-ink-muted-dark">{download.note}</p>
        </div>
      </Container>
    </footer>
  );
}
