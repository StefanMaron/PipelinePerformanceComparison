/// <summary>
/// Coverage Report Builder - Processes Code Coverage data into structured JSON gap reports.
///
/// After running tests with CodeCoverageMgt.Start/Stop, call BuildAndStore() to
/// read the collected coverage data and persist it in IsolatedStorage for API retrieval.
///
/// Storage: IsolatedStorage key 'CoverageGapReport' (DataScope::Module)
///
/// JSON Output Format:
/// {
///   "summary": {"totalLines": N, "coveredLines": N, "uncoveredLines": N, "coveragePercent": N},
///   "objects": [
///     {"type": "Codeunit", "id": 74304, "name": "...", "coverage": 85.5, "uncovered": ["45-48", "62"]}
///   ]
/// }
/// </summary>
codeunit 50004 "Coverage Report Builder"
{
    procedure BuildAndStore()
    var
        CodeCoverage: Record "Code Coverage";
        AllObj: Record AllObjWithCaption;
        RootObj: JsonObject;
        SummaryObj: JsonObject;
        ObjectsArray: JsonArray;
        ObjectEntry: JsonObject;
        UncoveredArray: JsonArray;
        TotalLines: Integer;
        CoveredLinesTotal: Integer;
        ObjTotalLines: Integer;
        ObjCoveredLines: Integer;
        CurrentObjType: Integer;
        CurrentObjId: Integer;
        InUncoveredRange: Boolean;
        RangeStart: Integer;
        RangeEnd: Integer;
        ObjCoveragePct: Decimal;
        OverallCoveragePct: Decimal;
        ObjName: Text;
        ResultJson: Text;
        IsFirstObject: Boolean;
    begin
        IsFirstObject := true;
        CurrentObjType := -1;
        CurrentObjId := -1;
        TotalLines := 0;
        CoveredLinesTotal := 0;

        // Only process executable code lines (Line Type = 0 = Code)
        CodeCoverage.SetCurrentKey("Object Type", "Object ID", "Line No.");
        CodeCoverage.SetRange("Line Type", CodeCoverage."Line Type"::Code);

        if CodeCoverage.FindSet() then
            repeat
                // Object boundary: flush previous object and start tracking the new one
                if (CodeCoverage."Object Type" <> CurrentObjType) or (CodeCoverage."Object ID" <> CurrentObjId) then begin
                    if not IsFirstObject then begin
                        // Close any open uncovered range
                        if InUncoveredRange then begin
                            AddRangeEntry(UncoveredArray, RangeStart, RangeEnd);
                            InUncoveredRange := false;
                        end;

                        // Accumulate totals
                        TotalLines += ObjTotalLines;
                        CoveredLinesTotal += ObjCoveredLines;

                        if ObjTotalLines > 0 then
                            ObjCoveragePct := Round(ObjCoveredLines / ObjTotalLines * 100, 0.01)
                        else
                            ObjCoveragePct := 100;

                        // Look up display name
                        AllObj.Reset();
                        AllObj.SetRange("Object ID", CurrentObjId);
                        if AllObj.FindFirst() then
                            if AllObj."Object Caption" <> '' then
                                ObjName := AllObj."Object Caption"
                            else
                                ObjName := AllObj."Object Name"
                        else
                            ObjName := '';

                        Clear(ObjectEntry);
                        ObjectEntry.Add('type', GetObjectTypeName(CurrentObjType));
                        ObjectEntry.Add('id', CurrentObjId);
                        ObjectEntry.Add('name', ObjName);
                        ObjectEntry.Add('coverage', ObjCoveragePct);
                        ObjectEntry.Add('uncovered', UncoveredArray);
                        ObjectsArray.Add(ObjectEntry);
                    end;

                    // Begin tracking the new object
                    CurrentObjType := CodeCoverage."Object Type";
                    CurrentObjId := CodeCoverage."Object ID";
                    ObjTotalLines := 0;
                    ObjCoveredLines := 0;
                    Clear(UncoveredArray);
                    InUncoveredRange := false;
                    IsFirstObject := false;
                end;

                // Tally this line
                ObjTotalLines += 1;
                if CodeCoverage."No. of Hits" > 0 then begin
                    ObjCoveredLines += 1;
                    if InUncoveredRange then begin
                        // Covered line closes the preceding gap range
                        AddRangeEntry(UncoveredArray, RangeStart, RangeEnd);
                        InUncoveredRange := false;
                    end;
                end else begin
                    // Uncovered line: extend current gap or start a new one
                    if InUncoveredRange then
                        RangeEnd := CodeCoverage."Line No."
                    else begin
                        InUncoveredRange := true;
                        RangeStart := CodeCoverage."Line No.";
                        RangeEnd := CodeCoverage."Line No.";
                    end;
                end;
            until CodeCoverage.Next() = 0;

        // Flush the final object
        if not IsFirstObject then begin
            if InUncoveredRange then
                AddRangeEntry(UncoveredArray, RangeStart, RangeEnd);

            TotalLines += ObjTotalLines;
            CoveredLinesTotal += ObjCoveredLines;

            if ObjTotalLines > 0 then
                ObjCoveragePct := Round(ObjCoveredLines / ObjTotalLines * 100, 0.01)
            else
                ObjCoveragePct := 100;

            AllObj.Reset();
            AllObj.SetRange("Object ID", CurrentObjId);
            if AllObj.FindFirst() then
                if AllObj."Object Caption" <> '' then
                    ObjName := AllObj."Object Caption"
                else
                    ObjName := AllObj."Object Name"
            else
                ObjName := '';

            Clear(ObjectEntry);
            ObjectEntry.Add('type', GetObjectTypeName(CurrentObjType));
            ObjectEntry.Add('id', CurrentObjId);
            ObjectEntry.Add('name', ObjName);
            ObjectEntry.Add('coverage', ObjCoveragePct);
            ObjectEntry.Add('uncovered', UncoveredArray);
            ObjectsArray.Add(ObjectEntry);
        end;

        // Build overall summary
        if TotalLines > 0 then
            OverallCoveragePct := Round(CoveredLinesTotal / TotalLines * 100, 0.01)
        else
            OverallCoveragePct := 0;

        SummaryObj.Add('totalLines', TotalLines);
        SummaryObj.Add('coveredLines', CoveredLinesTotal);
        SummaryObj.Add('uncoveredLines', TotalLines - CoveredLinesTotal);
        SummaryObj.Add('coveragePercent', OverallCoveragePct);

        RootObj.Add('summary', SummaryObj);
        RootObj.Add('objects', ObjectsArray);
        RootObj.WriteTo(ResultJson);

        IsolatedStorage.Set('CoverageGapReport', ResultJson, DataScope::Module);
    end;

    local procedure AddRangeEntry(var GapsArray: JsonArray; StartLine: Integer; EndLine: Integer)
    var
        RangeText: Text;
    begin
        if StartLine = EndLine then
            RangeText := Format(StartLine)
        else
            RangeText := Format(StartLine) + '-' + Format(EndLine);
        GapsArray.Add(RangeText);
    end;

    local procedure GetObjectTypeName(ObjType: Integer): Text
    begin
        case ObjType of
            1: exit('Table');
            3: exit('Report');
            5: exit('Codeunit');
            6: exit('XmlPort');
            8: exit('Page');
            9: exit('Query');
            10: exit('MenuSuite');
            14: exit('PageExtension');
            15: exit('TableExtension');
            16: exit('ReportExtension');
            else exit('Object');
        end;
    end;
}
