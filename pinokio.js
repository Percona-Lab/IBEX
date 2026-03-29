import path from "path"
import { fileURLToPath } from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export default {
  version: "5.0",
  title: "Percona IBEX",
  description: "Integration Bridge for EXtended systems — MCP server connecting AI assistants to Slack, Notion, Jira, ServiceNow, Salesforce, and persistent memory. https://github.com/Percona-Lab/IBEX",
  icon: "branding/icon.png",
  menu: async (kernel, info) => {
    let installing = info.running("install.js")
    let installed = info.exists("app/env")
    let running = info.running("start.js")
    let updating = info.running("update.js")
    let resetting = info.running("reset.js")

    if (installing) {
      return [{
        default: true,
        icon: "fa-solid fa-plug",
        text: "Installing",
        href: "install.js",
      }]
    } else if (installed) {
      if (running) {
        let local = kernel.memory.local[path.resolve(__dirname, "start.js")]
        if (local && local.url) {
          return [{
            popout: true,
            icon: "fa-solid fa-rocket",
            text: "Open IBEX",
            href: local.url,
          }, {
            icon: "fa-solid fa-terminal",
            text: "Terminal",
            href: "start.js",
          }]
        }
        return [{
          default: true,
          icon: "fa-solid fa-terminal",
          text: "Terminal",
          href: "start.js",
        }]
      } else if (updating) {
        return [{
          default: true,
          icon: "fa-solid fa-arrows-rotate",
          text: "Updating...",
          href: "update.js",
        }]
      } else if (resetting) {
        return [{
          default: true,
          icon: "fa-solid fa-broom",
          text: "Resetting...",
          href: "reset.js",
        }]
      } else {
        return [{
          default: true,
          icon: "fa-solid fa-power-off",
          text: "Start",
          href: "start.js",
        }, {
          icon: "fa-solid fa-arrows-rotate",
          text: "Update",
          href: "update.js",
        }, {
          icon: "fa-solid fa-plug",
          text: "Reinstall",
          href: "install.js",
        }, {
          icon: "fa-solid fa-broom",
          text: "Factory Reset",
          href: "reset.js",
        }]
      }
    } else {
      return [{
        default: true,
        icon: "fa-solid fa-plug",
        text: "Install",
        href: "install.js",
      }]
    }
  }
}
