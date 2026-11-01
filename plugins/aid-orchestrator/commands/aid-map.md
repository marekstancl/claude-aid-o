---
name: aid-map
description: Draw a process map, publish its clickable page, or read and answer the PM's marks on it
user_invocable: true
---

# /aid-map — Process Maps

**Last Updated:** 2026-11-01

Draw a process as a map in one fixed look (BPMN, or a state diagram), give the PM a page where a click shows
a step and a mark says what is wrong, and answer those marks. Optional: plans without maps never meet this.
Standard: `/ecosystem/specs/procesni-mapy`. The procedure is in `skills/process-maps/SKILL.md` - follow it.

## Arguments

```
/aid-map <process>            draw or redraw the map of a process and send the link
/aid-map --oznaceni [<name>]  read the PM's new marks and answer them ("podívej se na moje označení");
                              without a name, every map in docs/procesy/
/aid-map --docs <name>        put the map into the project's documentation (only when the PM agrees)
```

Resolve `$AID_PLUGIN_PATH` first, exactly as `commands/aid-plan.md` §Usage does.

## What it runs

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-process-map.sh" check   docs/procesy/<name>.mapa.yaml
bash "$AID_PLUGIN_PATH/scripts/aid-process-map.sh" publish docs/procesy/<name>.mapa.yaml
bash "$AID_PLUGIN_PATH/scripts/aid-process-map.sh" flags   docs/procesy/<name>.mapa.yaml --nove
bash "$AID_PLUGIN_PATH/scripts/aid-process-map.sh" flags   docs/procesy/<name>.mapa.yaml --zodpovezeno <mark id>
bash "$AID_PLUGIN_PATH/scripts/aid-process-map.sh" docs    docs/procesy/<name>.mapa.yaml --do <docusaurus path>
```

Output to the PM: one line with the link (`link <url>`), or the local path (`local <page>`) when no
publisher is configured. Marks are answered in the chat, one finding each, with options and a recommendation.

---

**Last Updated:** 2026-11-01
