const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/specprompt_web.ex",
    "../lib/specprompt_web/**/*.*ex"
  ],
  theme: {
    extend: {},
  },
  plugins: []
}
