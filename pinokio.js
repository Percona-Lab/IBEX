const path = require("path")
module.exports = {
  version: "3.4.0",
  title: "Percona IBEX",
  description: "Integration Bridge for EXtended systems — MCP server connecting AI assistants to Slack, Notion, Jira, ServiceNow, Salesforce, and persistent memory. https://github.com/Percona-Lab/IBEX",
  icon: "branding/icon.png",
  menu: async (kernel, info) => {
    const installing = info.running("pinokio/install.js")
    const installed = info.exists("app/env")
    const running = info.running("pinokio/start.js")
    const updating = info.running("pinokio/update.js")
    const resetting = info.running("pinokio/reset.js")

    if (installing) {
      return [{
        default: true,
        icon: "fa-solid fa-plug",
        text: "Installing",
        href: "pinokio/install.js",
      }]
    }

    if (!installed) {
      return [{
        default: true,
        icon: "fa-solid fa-plug",
        text: "Install",
        href: "pinokio/install.js",
      }]
    }

    if (running) {
      const local = kernel.memory.local[path.resolve(__dirname, "pinokio/start.js")]
      if (local && local.url) {
        return [{
          popout: true,
          icon: "fa-solid fa-rocket",
          text: "Open IBEX",
          href: local.url,
        }, {
          icon: "fa-solid fa-terminal",
          text: "Terminal",
          href: "pinokio/start.js",
        }]
      }
      return [{
        default: true,
        icon: "fa-solid fa-terminal",
        text: "Terminal",
        href: "pinokio/start.js",
      }]
    }

    if (updating) {
      return [{
        default: true,
        icon: "fa-solid fa-arrows-rotate",
        text: "Updating...",
        href: "pinokio/update.js",
      }]
    }

    if (resetting) {
      return [{
        default: true,
        icon: "fa-solid fa-broom",
        text: "Resetting...",
        href: "pinokio/reset.js",
      }]
    }

    return [{
      default: true,
      icon: "fa-solid fa-power-off",
      text: "Start",
      href: "pinokio/start.js",
    }, {
      icon: "fa-solid fa-arrows-rotate",
      text: "Update",
      href: "pinokio/update.js",
    }, {
      icon: "fa-solid fa-plug",
      text: "Reinstall",
      href: "pinokio/install.js",
    }, {
      icon: "fa-solid fa-broom",
      text: "Factory Reset",
      href: "pinokio/reset.js",
    }]
  }
}
