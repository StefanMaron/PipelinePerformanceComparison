# Fix Plan: Failing Full Pipeline Jobs (Run #56)

## Problem

Both "Linux - Full Pipeline" and "Windows - Full Pipeline" fail during app publishing:
- **Linux step 17** "Publish compiled apps to BC container" → exit code 1 (7 seconds)
- **Windows step 12** "Publish app and run tests" → exit code 1 (13 seconds)

### Root Causes

1. **Global scope conflict**: The Dev Endpoint (HTTP POST to port 7049) publishes to Dev/Tenant scope, but the pre-installed System Application exists at **Global scope**. BC returns HTTP 422: "The extension could not be deployed because it is already deployed on another tenant."

2. **Wrong publish order**: Test toolkit apps (which depend on System Application) are currently published BEFORE the compiled System Application. They must come AFTER.

---

## Changes

### Linux Full Pipeline (lines ~1110-1273)

**Step A — New step: "Replace pre-installed System Application" (insert after "Fix BC auth config", before "Publish test toolkit apps")**

After the container is healthy and auth is fixed, use `docker exec` to run PowerShell inside the Wine BC container:

1. Uninstall the pre-installed System Application with `-Force` (cascades to all dependents including Business Foundation, Base App, Application, etc.)
2. Unpublish the pre-installed System Application
3. Publish our compiled System Application `.app` at Global scope using `Publish-NAVApp`
4. Sync with `-Mode ForceSync`
5. Install with `-Force`

```bash
docker exec "$BC_CONTAINER" pwsh -Command "
  \$ErrorActionPreference = 'Stop'
  \$svcPath = '/root/.local/share/wineprefixes/bc1/drive_c/Program Files/Microsoft Dynamics NAV/260/Service'
  Import-Module \"\$svcPath/Microsoft.Dynamics.Nav.Apps.Management.psd1\" -Force

  # Uninstall System Application (cascades to dependents)
  Write-Host 'Uninstalling pre-installed System Application...'
  Uninstall-NAVApp -ServerInstance BC -Name 'System Application' -Force
  Unpublish-NAVApp -ServerInstance BC -Name 'System Application'

  # Publish our compiled version
  Write-Host 'Publishing compiled System Application...'
  Publish-NAVApp -ServerInstance BC -Path '/path/to/compiled/sysapp.app' -SkipVerification
  Sync-NAVApp -ServerInstance BC -Name 'System Application' -Mode ForceSync
  Install-NAVApp -ServerInstance BC -Name 'System Application' -Force
"
```

The `.app` file path needs to be resolved — either copy it into the container first, or mount it. The compiled `.app` is at `bcapps-temp/src/System Application/App/*.app` (or copied to `.` during compilation).

**Step B — Keep "Publish test toolkit apps" as-is (now runs AFTER System App replacement)**

No changes needed, except it now correctly depends on our compiled System Application.

**Step C — Modify "Publish compiled apps to BC container"**

Remove the System Application publish logic (already done in Step A). Only publish the **System Application Test** app here. Keep the `|| exit 1` for the Test app.

### Windows Full Pipeline (lines ~1782-1874)

**Step A — Remove `-includeTestToolkit -includeTestLibrariesOnly` from `New-BcContainer`**

Currently at line 1796-1797. Remove these flags so the container starts clean (no pre-installed test toolkit). This avoids dependency conflicts when replacing the System Application.

**Step B — New step: "Replace pre-installed System Application" (insert after container creation, before "Publish app and run tests")**

Use `Publish-BcContainerApp` with Global scope:

```powershell
# Uninstall pre-installed System Application (cascades to dependents)
Invoke-ScriptInBcContainer -containerName bcserver -scriptblock {
    Uninstall-NAVApp -ServerInstance BC -Name "System Application" -Force -ErrorAction SilentlyContinue
    Unpublish-NAVApp -ServerInstance BC -Name "System Application" -ErrorAction SilentlyContinue
}

# Publish our compiled System Application at Global scope
Publish-BcContainerApp -containerName bcserver -appFile $sysAppFile.FullName `
    -skipVerification -sync -install -scope Global -syncMode ForceSync
```

**Step C — New step: "Publish test toolkit apps" (insert after System App, before tests)**

Publish test toolkit `.app` files (already downloaded in step 8 "Download test toolkit apps from BC artifact") in dependency order — same order as the Linux pipeline:

1. Any
2. Library Assert
3. Library Variable Storage
4. Test Runner
5. Permissions Mock
6. Business Foundation Test Libraries
7. System Application Test Library
8. Tests-TestLibraries

Use `Publish-BcContainerApp -scope Global -skipVerification -sync -install`.

**Step D — Modify "Publish app and run tests"**

Remove the System Application publish logic. Only publish the **System Application Test** and run tests.

---

## Summary of Publish Order (both platforms)

1. Container created and healthy
2. Auth configured (Linux only)
3. **NEW: Uninstall + unpublish pre-installed System Application**
4. **NEW: Publish compiled System Application (Global scope)**
5. Publish test toolkit apps (8 apps in dependency order)
6. Publish compiled System Application Test
7. Run tests

## Files Modified

- `.github/workflows/bc-performance-comparison.yml` — the only file changed
