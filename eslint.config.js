import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: ["dist/**", "node_modules/**", "elm-stuff/**", "playwright-report/**", "test-results/**"],
  },
  ...tseslint.configs.recommended,
  {
    files: ["web/**/*.ts", "tests/**/*.ts"],
    rules: {
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "no-restricted-properties": [
        "error",
        { object: "document", property: "write", message: "Unsafe DOM sink." },
      ],
      "no-restricted-syntax": [
        "error",
        {
          selector: "AssignmentExpression[left.property.name='innerHTML']",
          message: "innerHTML is an unsafe sink; build typed DOM instead.",
        },
        {
          selector: "AssignmentExpression[left.property.name='outerHTML']",
          message: "outerHTML is an unsafe sink; build typed DOM instead.",
        },
        {
          selector: "CallExpression[callee.name='eval']",
          message: "eval is forbidden.",
        },
        {
          selector: "NewExpression[callee.name='Function']",
          message: "new Function is forbidden.",
        },
      ],
    },
  },
);
