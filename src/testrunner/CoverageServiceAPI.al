/// <summary>
/// Code Coverage Service API - OData endpoint for retrieving coverage gap reports.
///
/// Endpoint: POST /api/custom/automation/v1.0/companies({id})/codeCoverageServices(1)/Microsoft.NAV.GetGapReport
/// Body: {"objectFilter": "74301-74310"}   (empty string = return all objects)
///
/// Prerequisites: Run tests via codeunitRunRequests first. The Test Runner API (cu50003)
/// automatically collects coverage during test execution and stores it in IsolatedStorage.
///
/// Response (OData wraps the Text return value):
///   {"value": "{\"summary\":{...},\"objects\":[...]}"}
///
/// The bc-test client unwraps the outer {"value": ...} and JSON-parses the inner string.
/// </summary>
page 50004 "Code Coverage Service API"
{
    PageType = API;
    APIPublisher = 'custom';
    APIGroup = 'automation';
    APIVersion = 'v1.0';
    EntityName = 'codeCoverageService';
    EntitySetName = 'codeCoverageServices';
    SourceTable = Integer;
    SourceTableView = where(Number = const(1));
    ODataKeyFields = Number;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(content)
        {
            group(General)
            {
                field(id; Rec.Number)
                {
                    ApplicationArea = All;
                    Caption = 'ID';
                    Editable = false;
                }
            }
        }
    }

    /// <summary>
    /// Returns the latest coverage gap report as a JSON string.
    /// </summary>
    /// <param name="objectFilter">
    /// Optional ID range filter e.g. "74301-74310". Empty = return all objects.
    /// Supports single value ("74304") and range ("74301-74310").
    /// </param>
    /// <returns>
    /// JSON string: {"summary":{"totalLines":N,...},"objects":[...]}
    /// OData wraps this as: {"value":"<json string>"}
    /// </returns>
    [ServiceEnabled]
    procedure GetGapReport(objectFilter: Text): Text
    var
        CoverageJson: Text;
    begin
        if not IsolatedStorage.Get('CoverageGapReport', DataScope::Module, CoverageJson) then
            CoverageJson := '{"summary":{"totalLines":0,"coveredLines":0,"uncoveredLines":0,"coveragePercent":0},"objects":[]}';

        if objectFilter <> '' then
            CoverageJson := FilterCoverageByRange(CoverageJson, objectFilter);

        exit(CoverageJson);
    end;

    /// <summary>
    /// Filters coverage JSON to include only objects within the specified ID range.
    /// </summary>
    local procedure FilterCoverageByRange(CoverageJson: Text; ObjectFilter: Text): Text
    var
        JsonObj: JsonObject;
        FullArray: JsonArray;
        FilteredArray: JsonArray;
        ObjectToken: JsonToken;
        ObjObj: JsonObject;
        IdToken: JsonToken;
        ObjectId: Integer;
        RangeStart: Integer;
        RangeEnd: Integer;
        DashPos: Integer;
        StartText: Text;
        EndText: Text;
        ArrToken: JsonToken;
        ResultJson: Text;
    begin
        if not JsonObj.ReadFrom(CoverageJson) then
            exit(CoverageJson);

        // Parse filter: "74301-74310" or single "74304"
        DashPos := StrPos(ObjectFilter, '-');
        if DashPos > 0 then begin
            StartText := CopyStr(ObjectFilter, 1, DashPos - 1);
            EndText := CopyStr(ObjectFilter, DashPos + 1);
            if not Evaluate(RangeStart, StartText) then exit(CoverageJson);
            if not Evaluate(RangeEnd, EndText) then exit(CoverageJson);
        end else begin
            if not Evaluate(RangeStart, ObjectFilter) then exit(CoverageJson);
            RangeEnd := RangeStart;
        end;

        if not JsonObj.Get('objects', ArrToken) then
            exit(CoverageJson);

        FullArray := ArrToken.AsArray();
        foreach ObjectToken in FullArray do begin
            ObjObj := ObjectToken.AsObject();
            if ObjObj.Get('id', IdToken) then begin
                ObjectId := IdToken.AsValue().AsInteger();
                if (ObjectId >= RangeStart) and (ObjectId <= RangeEnd) then
                    FilteredArray.Add(ObjectToken);
            end;
        end;

        JsonObj.Replace('objects', FilteredArray);
        JsonObj.WriteTo(ResultJson);
        exit(ResultJson);
    end;
}
