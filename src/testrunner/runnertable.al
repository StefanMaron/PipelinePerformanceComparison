/// <summary>
/// Codeunit Run Request - State-tracked execution requests for the Test Runner API
///
/// This table stores execution requests with status tracking, providing a stateful
/// alternative to the stateless Test Runner API (codeunit 50199).
///
/// Purpose:
/// - Track codeunit execution requests with persistent state
/// - Store execution results and timestamps
/// - Enable asynchronous execution patterns via REST API
/// - Provide execution history with success/failure tracking
///
/// State Machine:
/// Pending → Running → Finished (success)
///                  → Error (failure)
///
/// API Endpoint:
/// /api/custom/automation/v1.0/codeunitRunRequests
///
/// Usage Pattern:
/// 1. POST to create new request with CodeunitId
/// 2. POST to .../Microsoft.NAV.runCodeunit action to execute
/// 3. GET to check Status and LastResult
/// 4. Query LastExecutionUTC for execution timestamp
/// </summary>
table 50003 "Codeunit Run Request"
{
    Caption = 'Codeunit Run Request';
    DataClassification = SystemMetadata;
    LookupPageId = "Codeunit Run Requests";
    DrillDownPageId = "Codeunit Run Requests";

    fields
    {
        /// <summary>
        /// Unique identifier for the execution request (GUID).
        /// </summary>
        /// <remarks>
        /// Auto-generated on insert if not provided.
        /// Used as OData key field for API access.
        /// </remarks>
        field(1; Id; Guid)
        {
            Caption = 'Id';
            DataClassification = SystemMetadata;
        }

        /// <summary>
        /// The ID of the codeunit to execute.
        /// </summary>
        /// <remarks>
        /// Must be set before calling RunCodeunit().
        /// No validation is performed - invalid IDs will result in Error status.
        /// </remarks>
        field(2; CodeunitId; Integer)
        {
            Caption = 'Codeunit Id';
            DataClassification = SystemMetadata;
        }

        /// <summary>
        /// Current execution status of the request.
        /// </summary>
        /// <remarks>
        /// Values:
        /// - Pending: Request created, not yet executed
        /// - Running: Execution in progress (set at start of RunCodeunit)
        /// - Finished: Execution completed successfully
        /// - Error: Execution failed (check LastResult for error message)
        /// </remarks>
        field(3; Status; Option)
        {
            Caption = 'Status';
            OptionMembers = Pending,Running,Finished,Error;
            DataClassification = SystemMetadata;
        }

        /// <summary>
        /// Result message from the last execution attempt.
        /// </summary>
        /// <remarks>
        /// Success: "Success"
        /// Failure: Contains the error message text
        /// Maximum length: 250 characters (error messages may be truncated)
        /// </remarks>
        field(4; LastResult; Text[250])
        {
            Caption = 'Last Result';
            DataClassification = SystemMetadata;
        }

        /// <summary>
        /// Timestamp of the last execution attempt (UTC timezone).
        /// </summary>
        /// <remarks>
        /// Updated by RunCodeunit() procedure.
        /// Always in UTC - convert to local time if needed for display.
        /// </remarks>
        field(5; LastExecutionUTC; DateTime)
        {
            Caption = 'Last Execution (UTC)';
            DataClassification = SystemMetadata;
        }
    }

    keys
    {
        /// <summary>
        /// Primary key on Id field.
        /// </summary>
        key(PK; Id) { Clustered = true; }
    }

    /// <summary>
    /// OnInsert trigger - Initializes new request records.
    /// </summary>
    /// <remarks>
    /// - Auto-generates GUID if not provided
    /// - Defaults Status to Pending (kept via no-op statement)
    /// </remarks>
    trigger OnInsert()
    begin
        if IsNullGuid(Id) then
            Id := CreateGuid();
        if Status = Status::Pending then; // keep default status
    end;
}

/// <summary>
/// Codeunit Run Requests API - REST endpoint for state-tracked codeunit execution
///
/// This API page exposes the Codeunit Run Request table via OData/REST endpoints,
/// enabling remote codeunit execution with persistent state tracking.
///
/// Endpoint:
/// /api/custom/automation/v1.0/codeunitRunRequests
///
/// Operations:
/// - GET: List all execution requests
/// - GET(id): Retrieve specific request by GUID
/// - POST: Create new execution request
/// - PATCH(id): Update request fields (e.g., CodeunitId)
/// - DELETE(id): Remove execution request
/// - POST(id)/Microsoft.NAV.runCodeunit: Execute the codeunit (service-enabled action)
/// </summary>
page 50002 "Codeunit Run Requests"
{
    PageType = API;
    Caption = 'Codeunit Run Requests';
    APIPublisher = 'custom';
    APIGroup = 'automation';
    APIVersion = 'v1.0';
    EntityName = 'codeunitRunRequest';
    EntitySetName = 'codeunitRunRequests';
    SourceTable = "Codeunit Run Request";
    DelayedInsert = true;
    ODataKeyFields = Id;

    layout
    {
        area(content)
        {
            group(General)
            {
                field(Id; Rec.Id) { Editable = false; }
                field(CodeunitId; Rec.CodeunitId) { }
                field(Status; Rec.Status) { Editable = false; }
                field(LastResult; Rec.LastResult) { Editable = false; }
                field(LastExecutionUTC; Rec.LastExecutionUTC) { Editable = false; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RunNow)
            {
                Caption = 'Run';
                ApplicationArea = All;
                trigger OnAction()
                begin
                    RunCodeunit();
                end;
            }
        }
    }

    /// <summary>
    /// Executes the codeunit specified in the CodeunitId field.
    /// Service-enabled procedure callable via REST API.
    /// </summary>
    /// <returns>True if execution succeeded, False if it failed</returns>
    /// <remarks>
    /// REST API Endpoint:
    /// POST .../codeunitRunRequests(guid'{id}')/Microsoft.NAV.runCodeunit
    ///
    /// Behavior:
    /// 1. Validates CodeunitId is set (TestField)
    /// 2. Prevents concurrent execution (checks for Running status)
    /// 3. Sets status to Running
    /// 4. Executes codeunit via Codeunit.Run()
    /// 5. Updates status to Finished (success) or Error (failure)
    /// 6. Captures error message in LastResult on failure
    /// 7. Records execution timestamp in LastExecutionUTC
    ///
    /// Error Handling:
    /// - Throws error if CodeunitId is not set
    /// - Throws error if already Running
    /// - Captures GetLastErrorText() on execution failure
    /// - Updates record even if execution fails
    ///
    /// Note: This does NOT use the Test Runner API (codeunit 50199).
    /// It directly calls Codeunit.Run() for simpler, stateful execution.
    /// </remarks>
    [ServiceEnabled]
    procedure RunCodeunit(): Boolean
    var
        TestRunnerAPI: Codeunit "Test Runner API";
        Log: Record "Log Table";
        Success: Boolean;
        FailedTests: Integer;
    begin
        Rec.TestField(CodeunitId);
        if Rec.Status = Rec.Status::Running then
            Error('Already running.');

        Rec.Status := Rec.Status::Running;
        Rec.Modify(true);

        // Use the Test Runner API to execute the codeunit
        // This properly handles both test codeunits (Subtype = Test) and regular codeunits
        ClearLastError();
        Commit(); // Required before running test codeunits to ensure clean transaction state

        TestRunnerAPI.SetCodeunitId(Rec.CodeunitId);
        Success := TestRunnerAPI.Run();

        // Check if any individual tests failed
        Log.SetRange(Success, false);
        FailedTests := Log.Count();

        if Success and (FailedTests = 0) then begin
            Rec.Status := Rec.Status::Finished;
            Rec.LastResult := 'Success';
        end else begin
            Rec.Status := Rec.Status::Error;
            if FailedTests > 0 then
                Rec.LastResult := StrSubstNo('%1 test(s) failed - check logs for details', FailedTests)
            else begin
                Rec.LastResult := CopyStr(GetLastErrorText(), 1, 250);
                if Rec.LastResult = '' then
                    Rec.LastResult := 'Unknown error - check logs for details';
            end;
        end;

        Rec.LastExecutionUTC := CurrentDateTime();
        Rec.Modify(true);
        exit(Success and (FailedTests = 0));
    end;
}