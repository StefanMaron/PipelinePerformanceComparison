/// <summary>
/// Sample data management codeunit for performance testing
/// </summary>
codeunit 50000 "Sample Data Management PPC"
{
    InherentPermissions = X;
    InherentEntitlements = X;
    Permissions = 
        tabledata "Sample Data PPC" = RIMD,
        tabledata "Sample Data Line PPC" = RIMD;
    
    /// <summary>
    /// Generates sample data for testing purposes
    /// </summary>
    procedure GenerateSampleData()
    var
        SampleData: Record "Sample Data PPC";
        SampleLine: Record "Sample Data Line PPC";
        i: Integer;
        j: Integer;
        NoOfRecords: Integer;
        NoOfLines: Integer;
    begin
        NoOfRecords := 100;
        NoOfLines := 5;
        
        for i := 1 to NoOfRecords do begin
            SampleData.Init();
            SampleData."Code" := 'SAMPLE' + Format(i, 0, '<Integer,3><Filler Character,0>');
            SampleData."Description" := 'Sample Description ' + Format(i);
            SampleData."Amount" := Random(10000);
            SampleData."Date" := CalcDate('<-' + Format(Random(365)) + 'D>', Today());
            SampleData."Status" := "Sample Status PPC"::Open;
            
            if SampleData.Insert() then begin
                for j := 1 to NoOfLines do begin
                    SampleLine.Init();
                    SampleLine."Document No." := SampleData."Code";
                    SampleLine."Line No." := j * 10000;
                    SampleLine."Item Code" := 'ITEM' + Format(Random(50), 0, '<Integer,3><Filler Character,0>');
                    SampleLine."Description" := 'Line Description ' + Format(j);
                    SampleLine."Quantity" := Random(100);
                    SampleLine."Unit Price" := Random(1000);
                    SampleLine.Validate();
                    SampleLine.Insert();
                end;
            end;
        end;
        
        Message('Generated %1 sample records with %2 lines each.', NoOfRecords, NoOfLines);
    end;
    
    /// <summary>
    /// Clears all sample data
    /// </summary>
    procedure ClearAllData()
    var
        SampleData: Record "Sample Data PPC";
        SampleLine: Record "Sample Data Line PPC";
    begin
        SampleLine.DeleteAll();
        SampleData.DeleteAll();
        
        Message('All sample data has been cleared.');
    end;
    
    /// <summary>
    /// Performs complex data processing for performance testing
    /// </summary>
    procedure ProcessLargeDataSet(): Integer
    var
        SampleData: Record "Sample Data PPC";
        SampleLine: Record "Sample Data Line PPC";
        TotalAmount: Decimal;
        RecordCount: Integer;
    begin
        SampleData.ReadIsolation := IsolationLevel::ReadUncommitted;
        SampleData.SetLoadFields("Code", "Amount");
        
        if SampleData.FindSet() then
            repeat
                SampleLine.ReadIsolation := IsolationLevel::ReadUncommitted;
                SampleLine.SetRange("Document No.", SampleData."Code");
                SampleLine.SetLoadFields("Amount");
                
                if SampleLine.FindSet() then
                    repeat
                        TotalAmount += SampleLine.Amount;
                    until SampleLine.Next() = 0;
                
                RecordCount += 1;
            until SampleData.Next() = 0;
        
        exit(RecordCount);
    end;
    
    /// <summary>
    /// Validates user setup and permissions
    /// </summary>
    [NonDebuggable]
    procedure ValidateUserSetup(): Boolean
    var
        UserSetup: Record "User Setup";
        ErrorInfo: ErrorInfo;
    begin
        UserSetup.ReadIsolation := IsolationLevel::ReadUncommitted;
        UserSetup.SetLoadFields("E-Mail");
        
        if not UserSetup.Get(UserId()) then begin
            ErrorInfo.Message := 'User setup is required for this operation.';
            ErrorInfo.DetailedMessage := 'Please configure your user setup before proceeding.';
            
            if UserSetup.WritePermission() then begin
                ErrorInfo.AddNavigationAction('Open User Setup');
                ErrorInfo.PageNo := Page::"User Setup";
            end else
                ErrorInfo.Message := ErrorInfo.Message + ' Contact your administrator.';
            
            Error(ErrorInfo);
        end;
        
        exit(true);
    end;
}