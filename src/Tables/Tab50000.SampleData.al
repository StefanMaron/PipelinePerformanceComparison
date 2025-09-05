/// <summary>
/// Sample data table for performance testing
/// </summary>
table 50000 "Sample Data PPC"
{
    Caption = 'Sample Data';
    DataClassification = CustomerContent;
    
    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
        }
        
        field(10; "Code"; Code[20])
        {
            Caption = 'Code';
            NotBlank = true;
        }
        
        field(20; "Description"; Text[100])
        {
            Caption = 'Description';
        }
        
        field(30; "Amount"; Decimal)
        {
            Caption = 'Amount';
            DecimalPlaces = 2 : 5;
        }
        
        field(40; "Date"; Date)
        {
            Caption = 'Date';
        }
        
        field(50; "Status"; Enum "Sample Status PPC")
        {
            Caption = 'Status';
        }
        
        field(60; "Created By"; Code[50])
        {
            Caption = 'Created By';
            DataClassification = EndUserIdentifiableInformation;
            Editable = false;
        }
        
        field(70; "Created Date"; DateTime)
        {
            Caption = 'Created Date';
            Editable = false;
        }
        
        field(80; "Total Value"; Decimal)
        {
            Caption = 'Total Value';
            FieldClass = FlowField;
            CalcFormula = sum("Sample Data Line PPC".Amount where("Document No." = field("Code")));
            Editable = false;
        }
    }
    
    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        
        key(CodeKey; "Code")
        {
        }
        
        key(DateKey; "Date", "Status")
        {
        }
    }
    
    fieldgroups
    {
        fieldgroup(DropDown; "Code", "Description", "Amount")
        {
        }
        
        fieldgroup(Brick; "Code", "Description", "Amount", "Status")
        {
        }
    }
    
    trigger OnInsert()
    begin
        "Created By" := UserId();
        "Created Date" := CurrentDateTime();
    end;
}