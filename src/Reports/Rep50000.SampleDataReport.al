/// <summary>
/// Sample data report for performance testing
/// </summary>
report 50000 "Sample Data Report PPC"
{
    Caption = 'Sample Data Report';
    UsageCategory = ReportsAndAnalysis;
    ApplicationArea = All;
    
    dataset
    {
        dataitem(SampleData; "Sample Data PPC")
        {
            RequestFilterFields = "Code", "Status", "Date";
            
            column(EntryNo; "Entry No.")
            {
            }
            
            column(Code; "Code")
            {
            }
            
            column(Description; "Description")
            {
            }
            
            column(Amount; "Amount")
            {
                DecimalPlaces = 2 : 2;
            }
            
            column(Date; "Date")
            {
            }
            
            column(Status; "Status")
            {
            }
            
            column(TotalValue; "Total Value")
            {
                DecimalPlaces = 2 : 2;
            }
            
            dataitem(SampleLines; "Sample Data Line PPC")
            {
                DataItemLink = "Document No." = field("Code");
                
                column(LineNo; "Line No.")
                {
                }
                
                column(ItemCode; "Item Code")
                {
                }
                
                column(LineDescription; "Description")
                {
                }
                
                column(Quantity; "Quantity")
                {
                    DecimalPlaces = 0 : 5;
                }
                
                column(UnitPrice; "Unit Price")
                {
                    DecimalPlaces = 2 : 5;
                }
                
                column(LineAmount; "Amount")
                {
                    DecimalPlaces = 2 : 2;
                }
            }
        }
    }
    
    requestpage
    {
        SaveValues = true;
        
        layout
        {
            area(content)
            {
                group(Options)
                {
                    Caption = 'Options';
                    
                    field(IncludeLines; IncludeLines)
                    {
                        ApplicationArea = All;
                        Caption = 'Include Lines';
                        ToolTip = 'Include detail lines in the report.';
                    }
                    
                    field(ShowTotals; ShowTotals)
                    {
                        ApplicationArea = All;
                        Caption = 'Show Totals';
                        ToolTip = 'Show total calculations in the report.';
                    }
                }
            }
        }
    }
    
    var
        IncludeLines: Boolean;
        ShowTotals: Boolean;
}