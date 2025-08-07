// @ts-check

import eslint from "@eslint/js";
import eslintPluginPrettierRecommended from "eslint-plugin-prettier/recommended";
import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: [
      ".pnp.*",
      "stablecoin-starknet-private/**",
      "coverage/**",
      "target/**",
      "packages/**",
      "*.js",
      "*.mjs",
      "node_modules/**",
      "dist/**",
      "build/**",
    ],
  },
  {
    extends: [
      ...tseslint.configs.recommended,
      eslintPluginPrettierRecommended,
    ],
  },
  eslint.configs.recommended,
  tseslint.configs.recommended,
  {
    rules: {
      "@typescript-eslint/no-explicit-any": "off",
      "eol-last": ["error", "always"], // Enforce newline at end of file
    },
  },
);
