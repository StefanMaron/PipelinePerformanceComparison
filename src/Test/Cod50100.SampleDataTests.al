/// <summary>
/// Test codeunit for sample data functionality
/// </summary>
codeunit 50001 "Sample Data Tests PPC"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure TestGenerateSampleData()
    var
        SampleData: Record "Sample Data PPC";
        SampleLine: Record "Sample Data Line PPC";
        SampleDataMgmt: Codeunit "Sample Data Management PPC";
        InitialDataCount: Integer;
        InitialLineCount: Integer;
    begin
        // Setup
        InitialDataCount := SampleData.Count();
        InitialLineCount := SampleLine.Count();

        // Exercise
        SampleDataMgmt.GenerateSampleData();

        // Verify
        if SampleData.Count() <= InitialDataCount then
            Error('Sample data was not generated as expected');
        if SampleLine.Count() <= InitialLineCount then
            Error('Sample lines were not generated as expected');
    end;

    [Test]
    procedure TestClearAllData()
    var
        SampleData: Record "Sample Data PPC";
        SampleLine: Record "Sample Data Line PPC";
        SampleDataMgmt: Codeunit "Sample Data Management PPC";
    begin
        // Setup - Ensure we have some data
        SampleDataMgmt.GenerateSampleData();
        SampleDataMgmt.GenerateSampleDataLines();
        if SampleData.Count() = 0 then
            Error('No sample data was generated');
        if SampleLine.Count() = 0 then
            Error('No sample lines were generated');
        // Exercise
        SampleDataMgmt.ClearAllData();

        // Verify
        if SampleData.Count() <> 0 then
            Error('All sample data should be cleared');
        Assert.AreEqual(0, SampleLine.Count(), 'All sample lines should be cleared');
    end;

    [Test]
    procedure TestProcessLargeDataSet()
    var
        SampleDataMgmt: Codeunit "Sample Data Management PPC";
        ProcessedCount: Integer;
    begin
        // Setup
        SampleDataMgmt.GenerateSampleData();

        // Exercise
        ProcessedCount := SampleDataMgmt.ProcessLargeDataSet();

        // Verify
        if ProcessedCount <= 0 then
            Error('Should process at least one record');
    end;

    [Test]
    procedure TestSampleDataValidation()
    var
        SampleData: Record "Sample Data PPC";
    begin
        // Setup
        SampleData.Init();
        SampleData."Code" := 'TEST001';
        SampleData."Description" := 'Test Description';
        SampleData."Amount" := 1000;
        SampleData."Date" := Today();
        SampleData."Status" := "Sample Status PPC"::Open;

        // Exercise & Verify
        if not SampleData.Insert() then
            Error('Should be able to insert valid sample data');

        // Cleanup
        SampleData.Delete();
    end;

    [Test]
    procedure TestSampleLineCalculation()
    var
        SampleLine: Record "Sample Data Line PPC";
        ExpectedAmount: Decimal;
    begin
        // Setup
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
    end;
}