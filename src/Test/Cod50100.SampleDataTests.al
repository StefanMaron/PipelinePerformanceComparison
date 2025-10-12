/// <summary>
/// Test codeunit for sample data functionality
/// </summary>
codeunit 50001 "Sample Data Tests PPC"
{
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions = tabledata "Sample Data Line PPC" = rimd,
                  tabledata "Sample Data PPC" = rimd;

    [Test]
    procedure TestGenerateSampleData()
    var
        SampleData: Record "Sample Data PPC";
        SampleLine: Record "Sample Data Line PPC";
        SampleDataMgmt: Codeunit "Sample Data Management PPC";
    begin
        // Setup - Clean existing data
        SampleDataMgmt.ClearAllData();

        // Exercise
        SampleDataMgmt.GenerateSampleData();

        // Verify
        if SampleData.Count() = 0 then
            Error('Sample data was not generated');
        if SampleLine.Count() = 0 then
            Error('Sample lines were not generated');

        // Cleanup
        SampleDataMgmt.ClearAllData();
    end;

    [Test]
    procedure TestClearAllData()
    var
        SampleData: Record "Sample Data PPC";
        SampleLine: Record "Sample Data Line PPC";
        SampleDataMgmt: Codeunit "Sample Data Management PPC";
    begin
        // Setup - Clean and generate data
        SampleDataMgmt.ClearAllData();
        SampleDataMgmt.GenerateSampleData();
        if SampleData.Count() = 0 then
            Error('No sample data was generated');
        if SampleLine.Count() = 0 then
            Error('No sample lines were generated');

        // Exercise
        SampleDataMgmt.ClearAllData();

        // Verify
        if SampleData.Count() <> 0 then
            Error('All sample data should be cleared');
        if SampleLine.Count() <> 0 then
            Error('All sample lines should be cleared');
    end;

    [Test]
    procedure TestProcessLargeDataSet()
    var
        SampleDataMgmt: Codeunit "Sample Data Management PPC";
        ProcessedCount: Integer;
    begin
        // Setup - Clean and generate data
        SampleDataMgmt.ClearAllData();
        SampleDataMgmt.GenerateSampleData();

        // Exercise
        ProcessedCount := SampleDataMgmt.ProcessLargeDataSet();

        // Verify
        if ProcessedCount <= 0 then
            Error('Should process at least one record');

        // Cleanup
        SampleDataMgmt.ClearAllData();
    end;

    [Test]
    procedure TestSampleDataValidation()
    var
        SampleData: Record "Sample Data PPC";
    begin
        // Setup - Clean any existing TEST001 record
        SampleData.SetRange("Code", 'TEST001');
        SampleData.DeleteAll(false);

        SampleData.Init();
        SampleData."Code" := 'TEST001';
        SampleData."Description" := 'Test Description';
        SampleData."Amount" := 1000;
        SampleData."Date" := Today();
        SampleData."Status" := "Sample Status PPC"::Open;

        // Exercise & Verify
        if not SampleData.Insert(false) then
            Error('Should be able to insert valid sample data');

        // Cleanup
        SampleData.Delete(false);
    end;

    [Test]
    procedure TestSampleLineCalculation()
    var
        SampleLine: Record "Sample Data Line PPC";
        ExpectedAmount: Decimal;
    begin
        // Setup - Clean any existing TEST001 line
        SampleLine.SetRange("Document No.", 'TEST001');
        SampleLine.SetRange("Line No.", 10000);
        SampleLine.DeleteAll(false);

        SampleLine.Init();
        SampleLine."Document No." := 'TEST001';
        SampleLine."Line No." := 10000;
        SampleLine."Quantity" := 10;
        SampleLine."Unit Price" := 25.50;

        // Exercise
        SampleLine.Insert(true);

        // Verify
        ExpectedAmount := 10 * 25.50;
        if ExpectedAmount <> SampleLine."Amount" then
            Error('Amount calculation is incorrect. Expected: %1, Actual: %2', ExpectedAmount, SampleLine."Amount");

        // Cleanup
        SampleLine.Delete(false);
    end;
}