module BigShift
  class RedshiftTableSchema
    def initialize(schema_name, table_name, redshift_connection)
      @schema_name = schema_name
      @table_name = table_name
      @redshift_connection = redshift_connection
    end

    def columns
      @columns ||= begin
        rows = @redshift_connection.exec_params(%|SELECT "column", "type", "notnull" FROM "pg_table_def" WHERE "schemaname" = $1 AND "tablename" = $2|, [@schema_name, @table_name])
        if rows.count == 0
          raise sprintf('Table %s for schema %s not found', @table_name.inspect, @schema_name.inspect)
        else
          columns = rows.map do |row|
            name = row['column']
            type = row['type']
            nullable = row['notnull'] == 'f'
            Column.new(name, type, nullable)
          end
          columns.sort_by!(&:name)
          columns
        end
      end
    end

    def to_big_query
      Google::Apis::BigqueryV2::TableSchema.new(fields: columns.map(&:to_big_query))
    end

    class Column
      attr_reader :name, :type

      def initialize(name, type, nullable)
        @name = name
        @type = type
        @nullable = nullable
      end

      def nullable?
        @nullable
      end

      def to_big_query
        Google::Apis::BigqueryV2::TableFieldSchema.new(
          name: @name,
          type: big_query_type,
          mode: @nullable ? 'NULLABLE' : 'REQUIRED'
        )
      end

      def to_sql
        case @type
        when /^numeric/, /int/, /^double/, 'real'
          sprintf('"%s"', @name)
        when /^character/
          sprintf(%q<('"' || REPLACE(REPLACE(REPLACE("%s", '"', '""'), '\\n', ''), '\\r', '') || '"')>, @name)
        when /^timestamp/
          sprintf(%q<(TO_CHAR("%s", 'YYYY-MM-DD HH24:MI:SS'))>, @name)
        when 'date'
          sprintf(%q<(TO_CHAR("%s", 'YYYY-MM-DD'))>, @name)
        when 'boolean'
          if nullable?
            sprintf('(CASE WHEN "%s" IS NULL THEN NULL WHEN "%s" THEN 1 ELSE 0 END)', @name, @name)
          else
            sprintf('(CASE WHEN "%s" THEN 1 ELSE 0 END)', @name)
          end
        else
          raise sprintf('Unsupported column type: %s', type.inspect)
        end
      end

      private

      def big_query_type
        case @type
          when /^character/ then
            'STRING'
          when /^date/ then
            'DATE'
          when /^timestamp/ then
            'TIMESTAMP'
          when /int/ then
            'INTEGER'
          when 'boolean' then
            'BOOLEAN'
          when /^double/, 'real', 'numeric' then
            'FLOAT'
          else
            raise sprintf('Unsupported column type: %s', type.inspect)
        end
      end
    end
  end
end
