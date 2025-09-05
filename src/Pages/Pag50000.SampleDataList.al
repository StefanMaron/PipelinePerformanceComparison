/// <summary>
/// Sample data list page
/// </summary>
page 50000 "Sample Data List PPC"
{
    Caption = 'Sample Data List';
    PageType = List;
    SourceTable = "Sample Data PPC";
    UsageCategory = Lists;
    ApplicationArea = All;
    
    layout
    {
        area(content)
        {
            repeater(General)
            {
                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the entry number.';
                }
                
                field("Code"; Rec."Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the code.';
                }
                
                field("Description"; Rec."Description")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the description.';
                }
                
                field("Amount"; Rec."Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the amount.';
                }
                
                field("Date"; Rec."Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the date.';
                }
                
                field("Status"; Rec."Status")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the status.';
                }
                
                field("Total Value"; Rec."Total Value")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the total value from related lines.';
                }
            }
        }
    }
    
    actions
    {
        area(processing)
        {
            action("Generate Sample Data")
            {
                ApplicationArea = All;
                Caption = 'Generate Sample Data';
                Image = CreateDocuments;
                ToolTip = 'Generate sample data for testing.';
                
                trigger OnAction()
                var
                    SampleDataMgmt: Codeunit "Sample Data Management PPC";
                begin
                    SampleDataMgmt.GenerateSampleData();
                    CurrPage.Update(false);
                end;
            }
            
            action("Clear Data")
            {
                ApplicationArea = All;
                Caption = 'Clear Data';
                Image = Delete;
                ToolTip = 'Clear all sample data.';
                
                trigger OnAction()
                var
                    SampleDataMgmt: Codeunit "Sample Data Management PPC";
                begin
                    SampleDataMgmt.ClearAllData();
                    CurrPage.Update(false);
                end;
            }
        }
        
        area(navigation)
        {
            action("Lines")
            {
                ApplicationArea = All;
                Caption = 'Lines';
                Image = Line;
                RunObject = Page "Sample Data Lines PPC";
                RunPageLink = "Document No." = field("Code");
                ToolTip = 'View the lines for this entry.';
            }
        }
    }
}