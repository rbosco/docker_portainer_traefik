import {
    AbsoluteFill,
    Audio,
    OffthreadVideo,
    Sequence,
    Series,
    interpolate,
    useCurrentFrame,
    useVideoConfig,
  } from "remotion";
  import { z } from "zod";
  
  // ============================================================================
  // Schema — contrato n8n ↔ Remotion. Validado pelo Zod antes do render.
  // ============================================================================
  
  const lowerThirdSchema = z.object({
    title: z.string(),
    subtitle: z.string().optional(),
  });
  
  const sceneSchema = z.object({
    id: z.number(),
    video_url: z.string().url(),
    audio_url: z.string().url().optional(),
    duration_s: z.number().positive(),
    subtitle_text: z.string().optional(),
    lower_third: lowerThirdSchema.optional(),
  });
  
  export const vslSchema = z.object({
    project_id: z.string(),
    fps: z.number().default(30),
  
    scenes: z.array(sceneSchema).min(1),
  
    overlays: z
      .object({
        subtitle_style: z.enum(["minimal", "bold", "karaoke"]).default("bold"),
        lower_thirds_enabled: z.boolean().default(true),
        cta_enabled: z.boolean().default(true),
      })
      .default({
        subtitle_style: "bold",
        lower_thirds_enabled: true,
        cta_enabled: true,
      }),
  
    cta: z
      .object({
        text: z.string(),
        duration_s: z.number().positive().default(5),
      })
      .optional(),
  
    bg_music: z
      .object({
        url: z.string().url(),
        volume: z.number().min(0).max(1).default(0.15),
      })
      .optional(),
  });
  
  export type VSLProps = z.infer<typeof vslSchema>;
  export type SceneProps = z.infer<typeof sceneSchema>;
  
  // ============================================================================
  // Cena individual — vídeo bruto + narração
  // ============================================================================
  
  const Scene: React.FC<{ scene: SceneProps; fps: number }> = ({ scene, fps }) => {
    const durationInFrames = Math.round(scene.duration_s * fps);
  
    return (
      <AbsoluteFill>
        <OffthreadVideo
          src={scene.video_url}
          muted={true}
          style={{ width: "100%", height: "100%", objectFit: "cover" }}
        />
        {scene.audio_url && (
          <Audio src={scene.audio_url} volume={1.0} />
        )}
      </AbsoluteFill>
    );
  };
  
  // ============================================================================
  // Overlay de legenda — renderiza o subtitle_text da cena atual
  // ============================================================================
  
  const SubtitleOverlay: React.FC<{
    scenes: SceneProps[];
    fps: number;
    style: "minimal" | "bold" | "karaoke";
  }> = ({ scenes, fps, style }) => {
    const frame = useCurrentFrame();
    const { height } = useVideoConfig();
  
    // Descobrir qual cena está ativa baseado no frame atual
    let cumulativeFrames = 0;
    let activeScene: SceneProps | null = null;
    for (const scene of scenes) {
      const sceneFrames = Math.round(scene.duration_s * fps);
      if (frame >= cumulativeFrames && frame < cumulativeFrames + sceneFrames) {
        activeScene = scene;
        break;
      }
      cumulativeFrames += sceneFrames;
    }
  
    if (!activeScene?.subtitle_text) return null;
  
    // Fade in/out suave
    const sceneStart = cumulativeFrames;
    const localFrame = frame - sceneStart;
    const sceneDuration = Math.round(activeScene.duration_s * fps);
    const opacity = interpolate(
      localFrame,
      [0, 5, sceneDuration - 5, sceneDuration],
      [0, 1, 1, 0],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
    );
  
    const fontSize = style === "bold" ? 52 : 44;
    const fontWeight = style === "bold" ? 800 : 600;
    // Posição adapta ao aspect ratio via height
    const bottomPct = height > 1600 ? 0.22 : 0.12;
  
    return (
      <AbsoluteFill
        style={{
          justifyContent: "flex-end",
          alignItems: "center",
          paddingBottom: height * bottomPct,
          pointerEvents: "none",
        }}
      >
        <div
          style={{
            backgroundColor: "rgba(0, 0, 0, 0.78)",
            color: "white",
            fontSize,
            fontWeight,
            padding: "20px 36px",
            borderRadius: 12,
            maxWidth: "82%",
            textAlign: "center",
            lineHeight: 1.25,
            fontFamily: "system-ui, -apple-system, sans-serif",
            letterSpacing: -0.5,
            opacity,
            textShadow: "0 2px 8px rgba(0,0,0,0.4)",
          }}
        >
          {activeScene.subtitle_text}
        </div>
      </AbsoluteFill>
    );
  };
  
  // ============================================================================
  // Lower third — chamada contextual durante cenas específicas
  // ============================================================================
  
  const LowerThirdOverlay: React.FC<{
    scenes: SceneProps[];
    fps: number;
  }> = ({ scenes, fps }) => {
    const frame = useCurrentFrame();
    const { height } = useVideoConfig();
  
    let cumulativeFrames = 0;
    let activeScene: SceneProps | null = null;
    let sceneStart = 0;
    for (const scene of scenes) {
      const sceneFrames = Math.round(scene.duration_s * fps);
      if (frame >= cumulativeFrames && frame < cumulativeFrames + sceneFrames) {
        activeScene = scene;
        sceneStart = cumulativeFrames;
        break;
      }
      cumulativeFrames += sceneFrames;
    }
  
    if (!activeScene?.lower_third) return null;
  
    const { title, subtitle } = activeScene.lower_third;
    const localFrame = frame - sceneStart;
  
    // Slide da esquerda nos primeiros 10 frames (~300ms)
    const translateX = interpolate(
      localFrame,
      [0, 10],
      [-400, 0],
      { extrapolateRight: "clamp" }
    );
  
    const bottomPct = height > 1600 ? 0.30 : 0.22;
  
    return (
      <AbsoluteFill
        style={{
          justifyContent: "flex-end",
          alignItems: "flex-start",
          paddingBottom: height * bottomPct,
          paddingLeft: 48,
          pointerEvents: "none",
        }}
      >
        <div
          style={{
            transform: `translateX(${translateX}px)`,
            display: "flex",
            flexDirection: "column",
            gap: 4,
          }}
        >
          <div
            style={{
              backgroundColor: "#0f172a",
              color: "white",
              padding: "12px 28px",
              fontSize: 32,
              fontWeight: 700,
              fontFamily: "system-ui, -apple-system, sans-serif",
              borderLeft: "6px solid #3b82f6",
            }}
          >
            {title}
          </div>
          {subtitle && (
            <div
              style={{
                backgroundColor: "#1e3a8a",
                color: "white",
                padding: "8px 28px",
                fontSize: 22,
                fontWeight: 500,
                fontFamily: "system-ui, -apple-system, sans-serif",
                borderLeft: "6px solid #3b82f6",
              }}
            >
              {subtitle}
            </div>
          )}
        </div>
      </AbsoluteFill>
    );
  };
  
  // ============================================================================
  // CTA — aparece nos últimos N segundos, pulsa
  // ============================================================================
  
  const CtaOverlay: React.FC<{
    cta: { text: string; duration_s: number };
    totalDurationFrames: number;
    fps: number;
  }> = ({ cta, totalDurationFrames, fps }) => {
    const frame = useCurrentFrame();
    const ctaFrames = Math.round(cta.duration_s * fps);
    const ctaStartFrame = totalDurationFrames - ctaFrames;
  
    if (frame < ctaStartFrame) return null;
  
    const localFrame = frame - ctaStartFrame;
  
    // Entrada em 15 frames
    const opacity = interpolate(localFrame, [0, 15], [0, 1], {
      extrapolateRight: "clamp",
    });
  
    // Pulse infinito (scale 1.0 <-> 1.05 em ciclo de ~800ms = 24 frames)
    const pulseFrame = localFrame % 24;
    const scale = interpolate(
      pulseFrame,
      [0, 12, 24],
      [1.0, 1.05, 1.0]
    );
  
    return (
      <AbsoluteFill
        style={{
          justifyContent: "center",
          alignItems: "center",
          pointerEvents: "none",
        }}
      >
        <div
          style={{
            background: "linear-gradient(135deg, #ef4444 0%, #dc2626 100%)",
            color: "white",
            fontSize: 64,
            fontWeight: 800,
            padding: "32px 64px",
            borderRadius: 16,
            boxShadow: "0 20px 60px rgba(220, 38, 38, 0.5)",
            fontFamily: "system-ui, -apple-system, sans-serif",
            textAlign: "center",
            maxWidth: "80%",
            opacity,
            transform: `scale(${scale})`,
            letterSpacing: -1,
          }}
        >
          {cta.text}
        </div>
      </AbsoluteFill>
    );
  };
  
  // ============================================================================
  // Música de fundo — com fade-in/out e ducking durante narração
  // ============================================================================
  
  const BackgroundMusic: React.FC<{
    bg_music: { url: string; volume: number };
    totalDurationFrames: number;
    fps: number;
    scenes: SceneProps[];
  }> = ({ bg_music, totalDurationFrames, fps, scenes }) => {
    const fadeFrames = Math.round(2 * fps); // 2s de fade
  
    // Duck: quando tem narração, abaixar pra 30% do volume normal
    // Implementado via volume function que Remotion aceita
    const volumeFn = (frame: number) => {
      // Fade-in
      const fadeIn = interpolate(frame, [0, fadeFrames], [0, 1], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      });
      // Fade-out
      const fadeOut = interpolate(
        frame,
        [totalDurationFrames - fadeFrames, totalDurationFrames],
        [1, 0],
        { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
      );
  
      // Descobrir se cena atual tem narração
      let cumulative = 0;
      let hasNarration = false;
      for (const scene of scenes) {
        const sceneFrames = Math.round(scene.duration_s * fps);
        if (frame >= cumulative && frame < cumulative + sceneFrames) {
          hasNarration = Boolean(scene.audio_url);
          break;
        }
        cumulative += sceneFrames;
      }
  
      const duckFactor = hasNarration ? 0.3 : 1.0;
      return bg_music.volume * fadeIn * fadeOut * duckFactor;
    };
  
    return <Audio src={bg_music.url} volume={volumeFn} />;
  };
  
  // ============================================================================
  // Componente principal VSL
  // ============================================================================
  
  export const VSL: React.FC<VSLProps> = ({
    scenes,
    overlays,
    cta,
    bg_music,
  }) => {
    const { fps } = useVideoConfig();
    const totalDurationFrames = scenes.reduce(
      (acc, s) => acc + Math.round(s.duration_s * fps),
      0
    );
  
    return (
      <AbsoluteFill style={{ backgroundColor: "black" }}>
        {/* Cenas em série */}
        <Series>
          {scenes.map((scene) => (
            <Series.Sequence
              key={scene.id}
              durationInFrames={Math.round(scene.duration_s * fps)}
            >
              <Scene scene={scene} fps={fps} />
            </Series.Sequence>
          ))}
        </Series>
  
        {/* Música de fundo (global) */}
        {bg_music && (
          <BackgroundMusic
            bg_music={bg_music}
            totalDurationFrames={totalDurationFrames}
            fps={fps}
            scenes={scenes}
          />
        )}
  
        {/* Overlays */}
        <SubtitleOverlay
          scenes={scenes}
          fps={fps}
          style={overlays.subtitle_style}
        />
  
        {overlays.lower_thirds_enabled && (
          <LowerThirdOverlay scenes={scenes} fps={fps} />
        )}
  
        {overlays.cta_enabled && cta && (
          <CtaOverlay
            cta={cta}
            totalDurationFrames={totalDurationFrames}
            fps={fps}
          />
        )}
      </AbsoluteFill>
    );
  };
  