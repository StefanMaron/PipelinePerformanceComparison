/// <summary>
/// Test codeunit for sample data functionality
/// </summary>
codeunit 50100 "Sample Data Tests PPC"
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
        Assert.IsTrue(SampleData.Count() > InitialDataCount, 'Sample data should be generated');
        Assert.IsTrue(SampleLine.Count() > InitialLineCount, 'Sample lines should be generated');
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
        Assert.IsTrue(SampleData.Count() > 0, 'Should have sample data');
        
        // Exercise
        SampleDataMgmt.ClearAllData();
        
        // Verify
        Assert.AreEqual(0, SampleData.Count(), 'All sample data should be cleared');
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
        Assert.IsTrue(ProcessedCount > 0, 'Should process at least one record');
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
        Assert.IsTrue(SampleData.Insert(), 'Should be able to insert valid sample data');
        
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
        SampleLine.Validate();
        
        // Verify
        ExpectedAmount := 10 * 25.50;
        Assert.AreEqual(ExpectedAmount, SampleLine."Amount", 'Amount should be calculated correctly');
    end;
    
    var
        Assert: Codeunit Assert;
}