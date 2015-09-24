-- TODO mdsouza: set sqlformat json
-- TODO mdsouza: find a bash prettify or node.js prettify file for this
-- TODO mdsouza: ordering of items

/* TODO
echo '{"hello": 1, "foo": "bar"}' | xargs -0 node -e "console.log(JSON.stringify(JSON.parse(process.argv[1]), null, 2))"
cat f113.json | xargs -0 node -e "console.log(JSON.stringify(JSON.parse(process.argv[1]), null, 2))" >? f113.json
cat f113.json | xargs -0 node -e "console.log(JSON.stringify(JSON.parse(process.argv[1]), null, 2))" > test.json

*/

set serveroutput on size 1000000
set feedback off
set verify off
set termout off


define APP_ID = '&1'
define SPOOL_FILENAME = '&2'

spool &SPOOL_FILENAME.
declare

  -- TODO mdsouza: remove logger references.
  -- l_scope logger_logs.scope%type := 'apex-diff';

  -- TODO mdsouza: check sizes and max dbms_output.put_line('');
  l_sql clob; -- varchar2(4000);

  -- TODO mdsouza: make this a cclb since used in replace and need space
  l_sql_template clob; -- TODO mdsouza: convert to constant?

  l_app_id apex_applications.application_id%type := &APP_ID.;

  type rec_apex_info is record(
    apex_view_name apex_dictionary.apex_view_name%type,
    cols varchar2(4000),
    order_by varchar2(4000),
    rn number,
    cnt number
  );

  type tab_apex_info is table of rec_apex_info index by pls_integer;

  l_apex_info tab_apex_info;

begin
  -- Templates
  -- TODO mdsouza: support sqlcl cursor format
  l_sql_template :=
'cursor(select %COLUMNS%
from %APEX_VIEW_NAME%
where application_id = %APP_ID%
order by %ORDER_BY%) "%APEX_VIEW_NAME%"';
  l_sql_template := replace(l_sql_template, '%APP_ID%', l_app_id);

  dbms_output.put_line('set sqlformat json');
  dbms_output.put_line('set feedback off');
  dbms_output.put_line('set termout off');
  dbms_output.put_line('');
  dbms_output.put_line('spool f' || l_app_id || '.json');


  -- Creating parent select statement
  dbms_output.put_line('select ');


  -- Get all the APEX views, and their columns
  select
    ad.apex_view_name,
    -- TODO mdsouza: org
    listagg(atc.column_name, ',') within group (order by adc.column_id) cols,
    listagg(
      case
        when atc.data_type like '%LOB' then null -- can't order by LOBs
        else atc.column_name
      end, ',')
      within group (order by adc.column_id) order_by,
    row_number() over (order by ad.apex_view_name) rn,
    count(1) over () cnt
  bulk collect into l_apex_info
  from
    apex_dictionary ad,
    all_tab_columns atc,
    (
      -- For column ids
      select apex_view_name, column_name, column_id
      from apex_dictionary
      where column_id != 0) adc
  where 1=1
    and ad.column_id = 0
    -- APEX views
    and ad.apex_view_name not like 'APEX_UI%' -- TODO mdsouza: exclude?
    and ad.apex_view_name not like 'APEX_TEAM%'
    and ad.apex_view_name not like 'APEX_WORKSPACE%'
    and ad.apex_view_name not like 'APEX_WS%'
    and ad.apex_view_name not in ('APEX_APPLICATIONS', 'APEX_APPLICATION_GROUPS','APEX_THEMES')
    and ad.apex_view_name != 'APEX_APPLICATION_TRANS_MAP' -- doesn't contain application_id
    -- APEX dictionary columns
    and atc.table_name = adc.apex_view_name(+)
    and atc.column_name = adc.column_name(+)
    -- Columns
    and atc.table_name = upper(ad.apex_view_name)
    -- TODO mdsouza: see http://www.apex-at-work.com/2010/11/select-current-apex-version-and-user.html
    and atc.owner = 'APEX_050000' -- TODO mdsouza: change this to dynamic
    and atc.column_name not in (
      'WORKSPACE',
      'WORKSPACE_DISPLAY_NAME',
      'APPLICATION_ID',
      'APPLICATION_NAME',
      -- TODO mdsouza: do we want to include the audit columns? Could be useful to see who made the changes (or at least a best guess effort)
      -- TODO mdsouza: make this an option, for now disable.
      -- 'LAST_UPDATED_BY',
      -- 'LAST_UPDATED_ON',
      -- 'CREATED_BY',
      -- 'CREATED_ON',
      'COMPONENT_SIGNATURE'
    )
    -- TODO mdsouza: valid?
    and atc.data_type not in ('BLOB')
  group by ad.apex_view_name
  order by rn;

  for i in 1 .. l_apex_info.count loop

    l_sql := replace(l_sql_template, '%COLUMNS%', l_apex_info(i).cols);
    l_sql := replace(l_sql, '%APEX_VIEW_NAME%', l_apex_info(i).apex_view_name);
    l_sql := replace(l_sql, '%ORDER_BY%', l_apex_info(i).order_by);
    l_sql := lower(l_sql);

    dbms_output.put_line(l_sql);

    if l_apex_info(i).rn != l_apex_info(i).cnt then
      dbms_output.put_line(','); -- Column/cursor delimeter
    end if;

  end loop; -- apex_dictionary

  -- Closing main query
  dbms_output.put_line('from dual;');

  dbms_output.put_line('');
  dbms_output.put_line('spool off');
  dbms_output.put_line('set sqlformat default');

  -- TODO mdsouza: make this an option
  dbms_output.put_line('');
  -- dbms_output.put_line('exit');

exception
  when others then
    -- logger.log_error('Unhandled Exception', l_scope);
    raise;
end;
/

spool off


@&SPOOL_FILENAME.

exit
