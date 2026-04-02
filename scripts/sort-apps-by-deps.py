#!/usr/bin/env python3
"""
sort-apps-by-deps.py — Sort .app files by dependency order

Reads app.json/NavxManifest from .app files (ZIP archives), builds
the dependency graph, and outputs the topologically sorted publish order.

Equivalent to Microsoft's Sort-AppFilesByDependencies.ps1 but in Python
for use in Linux pipelines.

Usage:
    python3 sort-apps-by-deps.py /path/to/apps/*.app
    python3 sort-apps-by-deps.py --dir /bc/artifacts/app/Extensions
    python3 sort-apps-by-deps.py --keep-only <app-id> --dir /path  # only deps of this app
"""

import argparse
import json
import os
import re
import sys
import zipfile
from collections import deque
from pathlib import Path


def read_app_info(app_path: str) -> dict | None:
    """Extract app ID, name, publisher, version, and dependencies from a .app file.

    Handles both regular .app files (with NavxManifest.xml at root) and
    R2R (Ready-to-Run) packages (with readytorunappmanifest.json + nested .app).
    """
    try:
        with zipfile.ZipFile(app_path) as z:
            names = z.namelist()

            # R2R packages: readytorunappmanifest.json at root, nested .app inside
            if "readytorunappmanifest.json" in names:
                manifest = json.loads(z.read("readytorunappmanifest.json"))
                app_id = manifest.get("EmbeddedAppId", "").lower()
                name = manifest.get("EmbeddedAppName", "")
                publisher = manifest.get("EmbeddedAppPublisher", "")
                version = manifest.get("EmbeddedAppVersion", "")

                # Dependencies from R2R manifest
                deps = []
                for dep in manifest.get("Dependencies", []):
                    dep_id = dep.get("AppId", dep.get("Id", "")).lower()
                    if dep_id:
                        deps.append({
                            "id": dep_id,
                            "name": dep.get("Name", ""),
                            "publisher": dep.get("Publisher", ""),
                            "version": dep.get("MinVersion", dep.get("Version", "")),
                        })

                # If R2R manifest has no deps, try reading the nested .app
                if not deps:
                    nested_app = manifest.get("EmbeddedAppFileName", "")
                    if nested_app and nested_app in names:
                        try:
                            nested_data = z.read(nested_app)
                            nested_info = _read_inner_app(nested_data)
                            if nested_info:
                                deps = nested_info.get("dependencies", [])
                        except Exception:
                            pass

                return {
                    "id": app_id,
                    "name": name,
                    "publisher": publisher,
                    "version": version,
                    "dependencies": deps,
                    "path": app_path,
                }

            # Regular .app files: NavxManifest.xml at root
            if "NavxManifest.xml" in names:
                xml = z.read("NavxManifest.xml").decode("utf-8", errors="replace")
                app_id = _xml_attr(xml, "Id") or _xml_attr(xml, "AppId") or ""
                name = _xml_attr(xml, "Name") or ""
                publisher = _xml_attr(xml, "Publisher") or ""
                version = _xml_attr(xml, "Version") or ""

                # Parse dependencies from XML
                deps = []
                # Match <Dependency> elements
                for m in re.finditer(
                    r"<Dependency[^>]*?/>|<Dependency[^>]*?>.*?</Dependency>",
                    xml,
                    re.DOTALL,
                ):
                    dep_xml = m.group(0)
                    dep_id = (
                        _xml_attr(dep_xml, "AppId")
                        or _xml_attr(dep_xml, "Id")
                        or ""
                    )
                    dep_name = _xml_attr(dep_xml, "Name") or ""
                    dep_publisher = _xml_attr(dep_xml, "Publisher") or ""
                    dep_version = _xml_attr(dep_xml, "MinVersion") or _xml_attr(dep_xml, "Version") or ""
                    if dep_id:
                        deps.append(
                            {
                                "id": dep_id.lower(),
                                "name": dep_name,
                                "publisher": dep_publisher,
                                "version": dep_version,
                            }
                        )

                return {
                    "id": app_id.lower(),
                    "name": name,
                    "publisher": publisher,
                    "version": version,
                    "dependencies": deps,
                    "path": app_path,
                }

            # Fallback: try app.json (some packages have it)
            if "app.json" in names:
                data = json.loads(z.read("app.json").decode("utf-8-sig"))
                deps = []
                for dep in data.get("dependencies", []):
                    dep_id = dep.get("id", dep.get("appId", "")).lower()
                    if dep_id:
                        deps.append(
                            {
                                "id": dep_id,
                                "name": dep.get("name", ""),
                                "publisher": dep.get("publisher", ""),
                                "version": dep.get("version", ""),
                            }
                        )
                return {
                    "id": data.get("id", "").lower(),
                    "name": data.get("name", ""),
                    "publisher": data.get("publisher", ""),
                    "version": data.get("version", ""),
                    "dependencies": deps,
                    "path": app_path,
                }

    except (zipfile.BadZipFile, KeyError, Exception) as e:
        print(f"  WARN: could not read {app_path}: {e}", file=sys.stderr)
    return None


def _read_inner_app(data: bytes) -> dict | None:
    """Read app info from a nested .app file (inside an R2R package)."""
    try:
        import io
        with zipfile.ZipFile(io.BytesIO(data)) as inner_z:
            if "NavxManifest.xml" in inner_z.namelist():
                xml = inner_z.read("NavxManifest.xml").decode("utf-8", errors="replace")
                deps = []
                for m in re.finditer(
                    r"<Dependency[^>]*?/>|<Dependency[^>]*?>.*?</Dependency>",
                    xml, re.DOTALL,
                ):
                    dep_xml = m.group(0)
                    dep_id = (_xml_attr(dep_xml, "AppId") or _xml_attr(dep_xml, "Id") or "")
                    if dep_id:
                        deps.append({
                            "id": dep_id.lower(),
                            "name": _xml_attr(dep_xml, "Name") or "",
                            "publisher": _xml_attr(dep_xml, "Publisher") or "",
                            "version": _xml_attr(dep_xml, "MinVersion") or "",
                        })
                return {"dependencies": deps}
    except Exception:
        pass
    return None


def _xml_attr(xml: str, attr: str) -> str | None:
    """Extract an XML attribute value by name."""
    m = re.search(rf'{attr}\s*=\s*"([^"]*)"', xml, re.IGNORECASE)
    return m.group(1) if m else None


def topo_sort(apps: dict, keep_only_id: str | None = None) -> list:
    """
    Topological sort of apps by dependencies.
    If keep_only_id is set, only return that app and its transitive dependencies.
    """
    # Build adjacency: app_id -> list of dependency app_ids
    all_ids = set(apps.keys())

    if keep_only_id:
        # Walk the dependency tree from keep_only_id
        keep_only_id = keep_only_id.lower()
        needed = set()

        def walk(app_id):
            if app_id in needed or app_id not in apps:
                return
            needed.add(app_id)
            for dep in apps[app_id]["dependencies"]:
                walk(dep["id"])

        walk(keep_only_id)
        all_ids = needed

    # Kahn's algorithm
    in_degree = {aid: 0 for aid in all_ids}
    reverse = {aid: [] for aid in all_ids}

    for aid in all_ids:
        for dep in apps[aid]["dependencies"]:
            dep_id = dep["id"]
            if dep_id in all_ids:
                in_degree[aid] += 1
                reverse[dep_id].append(aid)

    queue = deque([aid for aid, deg in in_degree.items() if deg == 0])
    order = []

    while queue:
        node = queue.popleft()
        order.append(node)
        for dependent in reverse.get(node, []):
            in_degree[dependent] -= 1
            if in_degree[dependent] == 0:
                queue.append(dependent)

    # Add any remaining (circular deps)
    remaining = [aid for aid in all_ids if aid not in order]
    order.extend(remaining)

    return order


def main():
    parser = argparse.ArgumentParser(
        description="Sort .app files by dependency order"
    )
    parser.add_argument("apps", nargs="*", help=".app files to analyze")
    parser.add_argument(
        "--dir", "-d", help="Directory to scan for .app files"
    )
    parser.add_argument(
        "--keep-only",
        help="App ID — output only this app and its transitive dependencies",
    )
    parser.add_argument(
        "--json", action="store_true", help="Output as JSON"
    )
    parser.add_argument(
        "--names-only", action="store_true", help="Output only app names"
    )
    parser.add_argument(
        "--paths-only", action="store_true", help="Output only file paths"
    )
    parser.add_argument(
        "--remove-list",
        help="App ID — output apps NOT in this app's dependency chain (for removal)",
    )

    args = parser.parse_args()

    # Collect .app files
    app_files = list(args.apps) if args.apps else []
    if args.dir:
        for root, dirs, files in os.walk(args.dir):
            for f in files:
                if f.endswith(".app"):
                    app_files.append(os.path.join(root, f))

    if not app_files:
        print("No .app files found", file=sys.stderr)
        sys.exit(1)

    # Read all app manifests
    apps = {}
    for path in app_files:
        info = read_app_info(path)
        if info and info["id"]:
            apps[info["id"]] = info

    print(f"Read {len(apps)} apps", file=sys.stderr)

    # Sort
    keep_id = args.keep_only or args.remove_list
    if args.remove_list:
        # Get the dependency closure, then invert
        needed_ids = set(topo_sort(apps, keep_only_id=args.remove_list))
        remove_order = [
            aid for aid in apps if aid not in needed_ids
        ]
        for aid in remove_order:
            app = apps[aid]
            if args.paths_only:
                print(app["path"])
            elif args.names_only:
                print(app["name"])
            else:
                print(f"{app['name']}\t{app['publisher']}\t{app['version']}\t{app['path']}")
        print(
            f"\nKeep: {len(needed_ids)}, Remove: {len(remove_order)}",
            file=sys.stderr,
        )
    else:
        order = topo_sort(apps, keep_only_id=args.keep_only)
        for aid in order:
            app = apps[aid]
            if args.json:
                print(
                    json.dumps(
                        {
                            "id": app["id"],
                            "name": app["name"],
                            "publisher": app["publisher"],
                            "version": app["version"],
                            "path": app["path"],
                            "deps": [d["name"] for d in app["dependencies"]],
                        }
                    )
                )
            elif args.paths_only:
                print(app["path"])
            elif args.names_only:
                print(app["name"])
            else:
                deps = ", ".join(d["name"] for d in app["dependencies"]) or "(none)"
                print(f"{app['name']}\t{app['version']}\t{deps}")


if __name__ == "__main__":
    main()
