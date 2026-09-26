import type { ReactNode } from "react";
import { Shot, type ShotName } from "./Shot";

const download = { href: "/Headroom.dmg", note: "macOS 14 or later · Apple silicon and Intel · 1.7 MB" };

export function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Compare />
        <Features />
        <Privacy />
        <Pricing />
        <Faq />
        <Closing />
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
    <section id={id} className={`py-20 sm:py-28 ${bg}`}>
      <Container>{children}</Container>
    </section>
  );
}

function Heading({ kicker, title, lead }: { kicker?: string; title: string; lead?: string }) {
  return (
    <div className="max-w-2xl">
      {kicker && <p className="mb-2 text-sm font-semibold text-accent">{kicker}</p>}
      <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">{title}</h2>
      {lead && <p className="mt-4 text-lg text-ink-muted dark:text-ink-muted-dark">{lead}</p>}
    </div>
  );
}

/** Until builds are notarized, macOS blocks the first launch. Shown under every download button. */
function FirstOpenNote() {
  return (
    <p className="max-w-md text-xs text-balance text-ink-muted dark:text-ink-muted-dark">
      Headroom isn't notarized yet, so macOS blocks the first launch. Click Done, then Open Anyway in System
      Settings &gt; Privacy &amp; Security.
    </p>
  );
}

function DownloadButton({ large = false }: { large?: boolean }) {
  const size = large ? "px-6 py-3.5 text-base" : "px-4 py-2 text-sm";
  return (
    <a
      href={download.href}
      download
      className={`inline-flex items-center gap-2 rounded-full bg-accent font-semibold text-white hover:bg-accent-strong ${size}`}
    >
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true">
        <path d="M8 2v8m0 0 3-3M8 10 5 7M3 13h10" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      Download for Mac
    </a>
  );
}

/* Sections */

function Nav() {
  const links = [
    ["#compare", "Compare"],
    ["#features", "Features"],
    ["#privacy", "Privacy"],
    ["#pricing", "Pricing"],
    ["#faq", "FAQ"],
  ] as const;
  return (
    <header className="sticky top-0 z-10 border-b border-line bg-paper/85 backdrop-blur dark:border-line-dark dark:bg-paper-dark/85">
      <Container className="flex h-14 items-center justify-between">
        <a href="#top" className="flex items-center gap-2.5 font-semibold">
          <img src="/icon-512.png" alt="" width="28" height="28" />
          Headroom
        </a>
        <nav className="hidden gap-6 text-sm text-ink-muted md:flex dark:text-ink-muted-dark">
          {links.map(([href, label]) => (
            <a key={href} href={href} className="hover:text-ink dark:hover:text-ink-dark">
              {label}
            </a>
          ))}
        </nav>
        <DownloadButton />
      </Container>
    </header>
  );
}

function Hero() {
  return (
    <section id="top" className="pt-16 pb-12 sm:pt-24">
      <Container>
        <div className="mx-auto max-w-3xl text-center">
          <h1 className="text-4xl font-semibold tracking-tight text-balance sm:text-6xl">See what's filling your Mac.</h1>
          <p className="mx-auto mt-5 max-w-2xl text-lg text-ink-muted sm:text-xl dark:text-ink-muted-dark">
            Headroom names what's inside System Data, from Xcode build data to a two-year-old iPhone backup, and clears
            the parts that are safe to clear. Free, native, and it never touches the network.
          </p>
          <div className="mt-8 flex flex-col items-center gap-3">
            <DownloadButton large />
            <p className="text-sm text-balance text-ink-muted dark:text-ink-muted-dark">{download.note}</p>
            <FirstOpenNote />
          </div>
        </div>
        <div className="mx-auto mt-14 max-w-5xl">
          <Shot name="overview" alt="Headroom's overview: a disk bar, a fill estimate, three items worth a look, and a grid of 250 MB squares colored by category." eager />
          <p className="mt-3 text-center text-sm text-ink-muted dark:text-ink-muted-dark">
            The real app, rendered with its built-in example data.
          </p>
        </div>
      </Container>
    </section>
  );
}

const comparison: [string, string, string][] = [
  ["What you see", "A dozen categories and one big System Data bar", "About 35 named sources plus what it discovers on your Mac"],
  ["App caches", "Inside System Data", "Per app, with the app's name"],
  ["Deleted-app leftovers", "Not shown", "Found in Application Support and Caches and named"],
  ["What clearing does", "Not explained", "Each item says whether it rebuilds, redownloads, or is gone for good"],
  ["Open apps", "Not checked", "Skips an item while its app is running"],
  ["Old projects", "Inside Documents or Developer", "Build folders confirmed by project files, with the last-worked date"],
  ["Warnings", "None", "Shown in the plan before anything moves, such as a device's only backup"],
  ["Undo", "Varies", "Everything goes to the Trash. The Trash tab restores in one click"],
  ["Price", "Included with macOS", "Free"],
];

function Compare() {
  return (
    <Section id="compare" tone="tint">
      <Heading
        kicker="Compare"
        title="Storage settings vs Headroom"
        lead="Apple's Storage settings shows one grey bar for System Data. Headroom splits it into sources and says what each one is."
      />
      {/* Phones get one card per row; the table needs three columns of room. */}
      <div className="mt-10 space-y-3 md:hidden">
        {comparison.map(([row, apple, ours]) => (
          <div key={row} className="rounded-2xl border border-line bg-paper p-5 dark:border-line-dark dark:bg-paper-dark">
            <h3 className="font-semibold">{row}</h3>
            <p className="mt-2 text-sm text-ink-muted dark:text-ink-muted-dark">
              <span className="font-medium">Storage settings:</span> {apple}
            </p>
            <p className="mt-1 text-sm">
              <span className="font-medium text-accent">Headroom:</span> {ours}
            </p>
          </div>
        ))}
      </div>
      <div className="mt-10 hidden overflow-hidden rounded-2xl border border-line bg-paper md:block dark:border-line-dark dark:bg-paper-dark">
        <table className="w-full text-left">
          <thead>
            <tr className="border-b border-line text-ink-muted dark:border-line-dark dark:text-ink-muted-dark">
              <th className="px-5 py-4 font-medium">&nbsp;</th>
              <th className="px-5 py-4 font-medium">Storage settings</th>
              <th className="px-5 py-4 font-semibold text-accent">Headroom</th>
            </tr>
          </thead>
          <tbody>
            {comparison.map(([row, apple, ours]) => (
              <tr key={row} className="border-b border-line last:border-0 dark:border-line-dark">
                <th scope="row" className="px-5 py-4 align-top font-medium">
                  {row}
                </th>
                <td className="px-5 py-4 align-top text-ink-muted dark:text-ink-muted-dark">{apple}</td>
                <td className="px-5 py-4 align-top">{ours}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-4 text-sm text-ink-muted dark:text-ink-muted-dark">
        Totals won't match Apple's exactly. Headroom measures files itself and groups them differently. Photos, Mail,
        Messages and iCloud Drive stay with their own apps; Headroom points you to the right setting instead.
      </p>
    </Section>
  );
}

type Feature = {
  id: string;
  kicker: string;
  title: string;
  body: ReactNode;
  shot: ShotName;
  alt: string;
  points: string[];
};

const features: Feature[] = [
  {
    id: "sources",
    kicker: "Named sources",
    title: "Every item has a name and an owner",
    body: "Headroom knows about 35 locations that developer tools, browsers and chat apps fill up, and it discovers per-app caches, old installers in Downloads, iPhone and iPad backups, and data left behind by deleted apps.",
    shot: "category-expanded",
    alt: "The Developer tools list with Xcode build data expanded to show its explanation and path.",
    points: [
      "Each row says what it is, who made it, and what happens if you clear it.",
      "Badges tell you at a glance: Rebuildable, Redownload, Leftover, Personal data, App-managed.",
      "App-managed items such as Docker's disk image can't be selected. Headroom shows the right setting instead.",
    ],
  },
  {
    id: "projects",
    kicker: "Project build folders",
    title: "Keep the code. Clear the build files.",
    body: "node_modules, target, .build, .venv, Pods, .next and Gradle build folders add up fast. Headroom only counts a folder when the project's own files confirm it, such as package.json next to node_modules. Your source code stays.",
    shot: "projects",
    alt: "The Project build folders list with four untouched projects checked and a Select untouched button.",
    points: [
      "Every folder shows the project it belongs to and when you last worked on it.",
      "Projects nobody has touched in 90 days get an Untouched tag.",
      "One button selects all of them.",
    ],
  },
  {
    id: "cleanup",
    kicker: "Safe cleanup",
    title: "Everything goes to the Trash first",
    body: "Nothing is ever preselected. You pick, Headroom shows a plan grouped by consequence, and it checks each item again right before moving it.",
    shot: "review",
    alt: "The cleanup plan grouped into Rebuildable, Can be downloaded again and Personal data, with a warning about app archives.",
    points: [
      "The plan lists warnings, such as a backup that is the device's only copy.",
      "Items are skipped if their app is open or the file that identified them is gone. The result says why, like \"2 skipped because Xcode was open\".",
      "The Trash tab lists what moved and puts any item back in one click.",
    ],
  },
  {
    id: "menubar",
    kicker: "Menu bar",
    title: "A heads-up before space runs out",
    body: "Each scan is compared with the last one, so Headroom can say what grew and roughly when the disk fills up if nothing changes.",
    shot: "menubar",
    alt: "The menu bar panel: 27.2 GB free of 494 GB, a fill estimate, three items worth a look, and toggles for the weekly check and low space alert.",
    points: [
      "Worth a look: sources that grew since the last scan and untouched projects, each with a button.",
      "Weekly check: an optional background scan, off by default.",
      "Low space alert: a notification when free space drops under 10%.",
    ],
  },
];

function Features() {
  return (
    <Section id="features">
      <Heading kicker="Features" title="What it does" />
      <div className="mt-6 space-y-20 sm:mt-10 sm:space-y-28">
        {features.map((feature, index) => (
          <FeatureRow key={feature.id} feature={feature} flip={index % 2 === 1} />
        ))}
      </div>
    </Section>
  );
}

function FeatureRow({ feature, flip }: { feature: Feature; flip: boolean }) {
  const narrow = feature.shot === "menubar" || feature.shot === "review";
  return (
    <div id={feature.id} className="grid items-center gap-8 lg:grid-cols-12 lg:gap-14">
      <div className={`lg:col-span-5 ${flip ? "lg:order-2" : ""}`}>
        <p className="mb-2 text-sm font-semibold text-accent">{feature.kicker}</p>
        <h3 className="text-2xl font-semibold tracking-tight sm:text-3xl">{feature.title}</h3>
        <p className="mt-4 text-ink-muted dark:text-ink-muted-dark">{feature.body}</p>
        <ul className="mt-5 space-y-2.5">
          {feature.points.map((point) => (
            <li key={point} className="flex gap-3">
              <Check />
              <span>{point}</span>
            </li>
          ))}
        </ul>
      </div>
      <div className={`lg:col-span-7 ${flip ? "lg:order-1" : ""} ${narrow ? "flex justify-center" : ""}`}>
        <Shot name={feature.shot} alt={feature.alt} className={narrow ? "shot w-full max-w-md" : "shot w-full"} />
      </div>
    </div>
  );
}

function Check() {
  return (
    <svg className="mt-1 h-4 w-4 shrink-0 text-accent" viewBox="0 0 16 16" fill="none" aria-hidden="true">
      <path d="m3 8.5 3 3 7-7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function Privacy() {
  const items: [string, string][] = [
    ["No network requests", "Headroom never connects to anything. No update check, no license check, no crash reports. You can watch it with a firewall and see nothing."],
    ["No account, no analytics", "There's nothing to sign up for and nothing is counted. The app keeps three small JSON files in Application Support: the last scan, scan history and the Trash log."],
    ["Full Disk Access is optional", "Without it, Headroom skips Mail, Messages, device backups and app containers, and lists exactly what it couldn't read so you know the totals are low."],
    ["Only names, sizes and dates", "Scanning reads file metadata. Headroom never opens your documents, photos or messages."],
  ];
  return (
    <Section id="privacy" tone="tint">
      <Heading kicker="Privacy" title="Nothing leaves your Mac" />
      <div className="mt-10 grid gap-5 sm:grid-cols-2">
        {items.map(([title, body]) => (
          <div key={title} className="rounded-2xl border border-line bg-paper p-6 dark:border-line-dark dark:bg-paper-dark">
            <h3 className="font-semibold">{title}</h3>
            <p className="mt-2 text-ink-muted dark:text-ink-muted-dark">{body}</p>
          </div>
        ))}
      </div>
    </Section>
  );
}

function Pricing() {
  const included = [
    "Every feature, on as many Macs as you like",
    "No license key, no account, no subscription",
    "Menu bar panel, weekly check and low space alert",
    "Example data mode to try everything without touching your disk",
    "CSV export of every scan (⌘E)",
  ];
  return (
    <Section id="pricing">
      <Heading kicker="Pricing" title="Free" lead="There's no license and nothing to pay. Download it and run it." />
      <div className="mt-10 max-w-md rounded-2xl border border-line p-8 dark:border-line-dark">
        <div className="flex items-baseline gap-2">
          <span className="text-5xl font-semibold tracking-tight">$0</span>
          <span className="text-ink-muted dark:text-ink-muted-dark">forever</span>
        </div>
        <ul className="mt-6 space-y-2.5">
          {included.map((item) => (
            <li key={item} className="flex gap-3">
              <Check />
              <span>{item}</span>
            </li>
          ))}
        </ul>
        <div className="mt-8">
          <DownloadButton large />
          <p className="mt-3 text-sm text-ink-muted dark:text-ink-muted-dark">{download.note}</p>
          <FirstOpenNote />
        </div>
      </div>
    </Section>
  );
}

const faq: [string, ReactNode][] = [
  [
    "macOS says it can't open Headroom. What now?",
    <>
      Headroom isn't notarized with Apple, so the first launch is blocked. Open System Settings, go to
      Privacy &amp; Security, scroll down to the message about Headroom and click <strong>Open Anyway</strong>. macOS
      asks once more, then the app opens normally from then on.
    </>,
  ],
  [
    "How do I install it?",
    "Open the .dmg and drag Headroom to Applications. There's no installer and nothing else gets written outside Application Support.",
  ],
  [
    "Could it delete something important?",
    "Only items you tick go to the Trash, and nothing is ticked for you. Photos, Mail, Messages, iCloud Drive, Docker's disk image and simulator devices can't be selected at all. Right before each move, Headroom checks the item again and skips it if its app is open or the file that identified it is gone.",
  ],
  [
    "Why don't the numbers match Apple's Storage settings?",
    "Headroom measures allocated file sizes itself and groups them by source rather than by Apple's categories. macOS also counts local snapshots and purgeable space differently. A file hard-linked inside one folder counts once, but links shared between folders and APFS clones count in each place, which is why cleanup reports space as \"up to\" what you'll get back.",
  ],
  [
    "When does the space come back?",
    "When you empty the Trash. Headroom moves items there rather than deleting them, so you can put anything back from the Trash tab until then.",
  ],
  [
    "What can't it clear?",
    "Anything an app manages itself: the Photos library, Mail and Messages data, iCloud Drive, Docker's disk image and simulator devices. Headroom shows their size and points you to the setting that controls them.",
  ],
  [
    "Do I need to give it Full Disk Access?",
    "No. Without it, Headroom skips Mail, Messages, device backups and app containers, and lists what it couldn't read. With it, those show up too. Either way it only reads names, sizes and dates. The first scan also looks inside Documents, Desktop, Downloads and iCloud Drive, so macOS asks once for each folder.",
  ],
  [
    "Does it run in the background?",
    "Only if you turn on the weekly check. That also registers Headroom as a login item so the check can run. Both are off by default and can be turned off in Settings or the menu bar panel.",
  ],
  [
    "Which Macs does it run on?",
    "Any Mac with macOS 14 Sonoma or later, Apple silicon or Intel. The download is a universal build.",
  ],
];

function Faq() {
  return (
    <Section id="faq" tone="tint">
      <Heading kicker="FAQ" title="Questions" />
      <div className="mt-10 max-w-3xl divide-y divide-line rounded-2xl border border-line bg-paper dark:divide-line-dark dark:border-line-dark dark:bg-paper-dark">
        {faq.map(([question, answer]) => (
          <details key={question} className="group px-6 py-4">
            <summary className="flex cursor-pointer items-center justify-between gap-4 font-medium">
              {question}
              <svg className="h-4 w-4 shrink-0 text-ink-muted transition-transform group-open:rotate-180 dark:text-ink-muted-dark" viewBox="0 0 16 16" fill="none" aria-hidden="true">
                <path d="m4 6 4 4 4-4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </summary>
            <p className="mt-3 text-ink-muted dark:text-ink-muted-dark">{answer}</p>
          </details>
        ))}
      </div>
    </Section>
  );
}

function Closing() {
  return (
    <Section id="download">
      <div className="mx-auto max-w-2xl text-center">
        <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">Make room for what matters</h2>
        <p className="mt-4 text-lg text-ink-muted dark:text-ink-muted-dark">
          A scan takes a minute or two. Nothing moves until you say so.
        </p>
        <div className="mt-8 flex flex-col items-center gap-3">
          <DownloadButton large />
          <p className="text-sm text-balance text-ink-muted dark:text-ink-muted-dark">{download.note}</p>
          <FirstOpenNote />
        </div>
      </div>
    </Section>
  );
}

function Footer() {
  return (
    <footer className="border-t border-line py-10 text-sm text-ink-muted dark:border-line-dark dark:text-ink-muted-dark">
      <Container className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <p className="flex items-center gap-2">
          <img src="/icon-512.png" alt="" width="20" height="20" />
          Headroom. A little more room on your Mac.
        </p>
        <p>Native SwiftUI · Apple silicon and Intel · macOS 14 or later</p>
      </Container>
    </footer>
  );
}
