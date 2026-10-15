declare module "*.elm" {
  const Elm: {
    Main: {
      init(options: { node: HTMLElement; flags: unknown }): {
        ports: {
          toJs: { subscribe(callback: (value: unknown) => void): void };
          fromJs: { send(value: unknown): void };
        };
      };
    };
  };
  export { Elm };
}

declare module "*?raw" {
  const content: string;
  export default content;
}
