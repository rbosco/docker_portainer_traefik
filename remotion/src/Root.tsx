import { Composition } from "remotion";
import { HelloWorld, helloWorldSchema } from "./compositions/HelloWorld";

export const RemotionRoot: React.FC = () => {
  return (
    <>
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
    </>
  );
};
