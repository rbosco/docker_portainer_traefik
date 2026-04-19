import { Composition } from "remotion";
import { HelloWorld, helloWorldSchema } from "./compositions/HelloWorld";
import { VSL, vslSchema } from "./compositions/VSL";

// ============================================================================
// Duração calculada dinamicamente a partir das scenes
// O Remotion Studio precisa de uma duração para o preview estático.
// Em produção (POST /renders), a duração vem via inputProps.
// ============================================================================

const calculateDurationInFrames = (scenes: Array<{ duration_s: number }>, fps: number) =>
  scenes.reduce((acc, s) => acc + Math.round(s.duration_s * fps), 0);

// Mock defaultProps usados APENAS no Remotion Studio (preview local)
// Em produção o n8n manda props reais via inputProps do /renders
const MOCK_SCENES = [
  {
    id: 1,
    video_url: "https://storage.googleapis.com/remotion-example/tutorial.mp4",
    duration_s: 4,
    subtitle_text: "Cena 1 — exemplo com legenda",
    lower_third: { title: "Introdução", subtitle: "Narrador principal" },
  },
  {
    id: 2,
    video_url: "https://storage.googleapis.com/remotion-example/tutorial.mp4",
    duration_s: 4,
    subtitle_text: "Cena 2 — mesma URL pra simular cenas diferentes",
  },
  {
    id: 3,
    video_url: "https://storage.googleapis.com/remotion-example/tutorial.mp4",
    duration_s: 3,
    subtitle_text: "Cena 3 — preparando CTA",
  },
];

const MOCK_VSL_PROPS = {
  project_id: "mock_preview",
  fps: 30,
  scenes: MOCK_SCENES,
  overlays: {
    subtitle_style: "bold" as const,
    lower_thirds_enabled: true,
    cta_enabled: true,
  },
  cta: { text: "Clique no link abaixo", duration_s: 3 },
  // bg_music omitido no mock — cenário real tem arquivo no MinIO
};

const MOCK_DURATION_FRAMES = calculateDurationInFrames(MOCK_SCENES, 30);

export const RemotionRoot: React.FC = () => {
  return (
    <>
      {/* Composition original preservada */}
      <Composition
        id="HelloWorld"
        component={HelloWorld}
        durationInFrames={150}
        fps={30}
        width={1280}
        height={720}
        schema={helloWorldSchema}
        defaultProps={{ title: "Hello from Remotion + MinIO" }}
      />

      {/* VSL 9:16 (Reels, TikTok, Stories) */}
      <Composition
        id="VSL-9x16"
        component={VSL}
        durationInFrames={MOCK_DURATION_FRAMES}
        fps={30}
        width={1080}
        height={1920}
        schema={vslSchema}
        defaultProps={MOCK_VSL_PROPS}
        calculateMetadata={({ props }) => ({
          durationInFrames: calculateDurationInFrames(props.scenes, props.fps ?? 30),
          props,
        })}
      />

      {/* VSL 1:1 (Feed Instagram/Facebook) */}
      <Composition
        id="VSL-1x1"
        component={VSL}
        durationInFrames={MOCK_DURATION_FRAMES}
        fps={30}
        width={1080}
        height={1080}
        schema={vslSchema}
        defaultProps={MOCK_VSL_PROPS}
        calculateMetadata={({ props }) => ({
          durationInFrames: calculateDurationInFrames(props.scenes, props.fps ?? 30),
          props,
        })}
      />

      {/* VSL 16:9 (YouTube, placements largos) */}
      <Composition
        id="VSL-16x9"
        component={VSL}
        durationInFrames={MOCK_DURATION_FRAMES}
        fps={30}
        width={1920}
        height={1080}
        schema={vslSchema}
        defaultProps={MOCK_VSL_PROPS}
        calculateMetadata={({ props }) => ({
          durationInFrames: calculateDurationInFrames(props.scenes, props.fps ?? 30),
          props,
        })}
      />
    </>
  );
};
