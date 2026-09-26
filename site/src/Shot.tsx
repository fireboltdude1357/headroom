/** Screenshot names that exist in public/shots as -light and -dark WebP files. */
export type ShotName = "overview" | "projects" | "category-expanded" | "trash" | "review" | "result" | "menubar";

/** Pixel sizes of the WebP files, so the browser reserves space before they load. */
const sizes: Record<ShotName, { width: number; height: number }> = {
  overview: { width: 1600, height: 1047 },
  projects: { width: 1600, height: 1047 },
  "category-expanded": { width: 1600, height: 1047 },
  trash: { width: 1600, height: 1047 },
  review: { width: 1120, height: 1040 },
  result: { width: 920, height: 564 },
  menubar: { width: 640, height: 826 },
};

type Props = {
  name: ShotName;
  alt: string;
  className?: string;
  /** Hero images load eagerly; everything else waits until it scrolls near. */
  eager?: boolean;
};

/** A screenshot that swaps between its light and dark rendering with the system appearance. */
export function Shot({ name, alt, className, eager }: Props) {
  const { width, height } = sizes[name];
  return (
    <picture>
      <source srcSet={`/shots/${name}-dark.webp`} media="(prefers-color-scheme: dark)" />
      <img
        src={`/shots/${name}-light.webp`}
        alt={alt}
        width={width}
        height={height}
        loading={eager ? "eager" : "lazy"}
        decoding="async"
        className={className ?? "shot w-full"}
      />
    </picture>
  );
}
