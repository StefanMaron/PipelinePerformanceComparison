/// <summary>
/// Test Codeunit - Example implementation for the Test Runner API system
///
/// This codeunit demonstrates the pattern for creating testable/executable codeunits
/// that can be invoked remotely via the Test Runner API (codeunit 50199).
///
/// Purpose:
/// - Serves as a working example of a codeunit designed for remote execution
/// - Demonstrates logging execution results to the Log Table
/// - Shows how to access environment and server information
///
/// Execution:
/// - Can be executed via Test Runner API: RunCodeunit(50100)
/// - Can be executed via API endpoints: /api/.../codeunitRunRequests
/// - Each execution creates a log entry with timestamp and server information
///
/// Note: Debug Message() calls are commented out to support headless/API execution.
/// </summary>
codeunit 50002 "Test CU"
{
    Subtype = Test;

    /// <summary>
    /// OnRun trigger - Executed when the codeunit is invoked.
    /// </summary>
    /// <remarks>
    /// - Creates a log entry in the Log Table for audit trail
    /// - Captures the server computer name for distributed environment tracking
    /// - Message() calls are commented out to support API/headless execution
    /// - Demonstrates accessing environment information and server instance metadata
    /// </remarks>
    trigger OnRun()
    var
        Env: Codeunit "Environment Information";
        // ServerInstance: Record "Server Instance";
        Log: Record "Log Table";
    begin
        // Debug output - commented out for API execution compatibility
        //Message('Test CU is running');

        // Environment information retrieval example
        //Message('Current env name: %1', Env.GetEnvironmentName());

        // Server instance information retrieval example
        //if ServerInstance.Get(Database.ServiceInstanceId) then
        //    Message('Current server instance name: %1', ServerInstance."Service Name")
        //else
        //    Message('No server instance found');

        //Message('Current machine name: %1', ServerInstance."Server Computer Name");

        // Create audit log entry
        // This demonstrates the recommended pattern for tracking codeunit executions
        Log.Init();
        Log."Message" := 'Test CU ran successfully';
        Log."Computer Name" := 'GithubActions';
        Log.Insert();

    end;
}