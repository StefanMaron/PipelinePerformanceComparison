/// <summary>
/// Sample status enumeration
/// </summary>
enum 50000 "Sample Status PPC"
{
    Extensible = true;
    
    value(0; " ")
    {
        Caption = ' ';
    }
    
    value(1; "Open")
    {
        Caption = 'Open';
    }
    
    value(2; "In Progress")
    {
        Caption = 'In Progress';
    }
    
    value(3; "Completed")
    {
        Caption = 'Completed';
    }
    
    value(4; "Cancelled")
    {
        Caption = 'Cancelled';
    }
}