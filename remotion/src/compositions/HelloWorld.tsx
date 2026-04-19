import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { z } from "zod";

export const helloWorldSchema = z.object({
  title: z.string(),
});

export const HelloWorld: React.FC<z.infer<typeof helloWorldSchema>> = ({ title }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  const opacity = interpolate(frame, [0, 20, durationInFrames - 20, durationInFrames], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const scale = interpolate(frame, [0, 30], [0.8, 1], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill
      style={{
        background: "linear-gradient(135deg, #0f172a 0%, #1e3a8a 100%)",
        justifyContent: "center",
        alignItems: "center",
        fontFamily: "system-ui, sans-serif",
      }}
    >
      <div
        style={{
          color: "white",
          fontSize: 72,
          fontWeight: 700,
          opacity,
          transform: `scale(${scale})`,
          textAlign: "center",
          padding: "0 80px",
        }}
      >
        {title}
      </div>
    </AbsoluteFill>
  );
};
