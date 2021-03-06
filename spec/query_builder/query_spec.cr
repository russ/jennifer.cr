require "../spec_helper"

describe Jennifer::QueryBuilder::Query do
  described_class = Jennifer::QueryBuilder::Query

  describe "#to_sql" do
    context "if query tree is not epty" do
      it "retruns sql representation of condition" do
        q = Factory.build_query
        c = Factory.build_criteria
        q.set_tree(c).as_sql.should eq(c.as_sql)
      end
    end

    context "if query tree is empty" do
      it "returns empty string" do
        Factory.build_query.as_sql.should eq("")
      end
    end
  end

  describe "#sql_args" do
    context "if query tree is not epty" do
      it "retruns sql args of condition" do
        q = Factory.build_query
        c = Factory.build_criteria
        q.set_tree(c).sql_args.should eq(c.sql_args)
      end
    end

    context "if query tree is empty" do
      it "returns empty array" do
        Factory.build_query.sql_args.should eq([] of DB::Any)
      end
    end
  end

  describe "#set_tree" do
    context "argument is another query" do
      it "gets it's tree" do
        q1 = Factory.build_query
        q2 = Factory.build_query
        q1.set_tree(Factory.build_expression.c("f1"))
        q2.set_tree(q1)
        q1.tree.should be(q2.tree)
      end
    end

    context "has own tree" do
      it "makes AND with new criteria" do
        q1 = Factory.build_query
        c1 = Factory.build_criteria
        c2 = Factory.build_criteria(field: "f2")

        q1.set_tree(c1)
        q1.set_tree(c2)
        q1.tree.should be_a Jennifer::QueryBuilder::And
      end
    end

    context "is empty" do
      it "makes given criteria as own" do
        q1 = Factory.build_query
        c1 = Factory.build_criteria

        q1.set_tree(c1)
        q1.tree.as(Jennifer::QueryBuilder::Condition).lhs.should eq(c1)
      end
    end
  end

  describe "#select" do
    context "with string argument" do
      it "uses argument as raw sql" do
        described_class["table"].select("raw sql")._raw_select.should eq("raw sql")
      end
    end

    context "with symbol" do
      it "creates criteria for given fields and current table" do
        fields = described_class["table"].select(:f1)._select_fields
        fields.size.should eq(1)
        fields[0].field.should eq("f1")
        fields[0].table.should eq("table")
      end
    end

    context "with symbol tuple" do
      it "adds all as criteria" do
        fields = described_class["table"].select(:f1, :f2)._select_fields
        fields.size.should eq(2)
        fields[0].field.should eq("f1")
        fields[1].field.should eq("f2")
      end
    end

    context "with criteria" do
      it "adds it to select fields" do
        fields = described_class["table"].select(Contact._id)._select_fields
        fields.size.should eq(1)
        fields[0].field.should eq("id")
        fields[0].table.should eq("contacts")
      end

      context "as raw sql" do
        it "removes brackets" do
          field = described_class["table"].select(Contact.context.sql("some sql"))._select_fields[0]
          field.identifier.should eq("some sql")
        end
      end
    end

    context "with array of criterias" do
      it "removes brackets for all raw sql" do
        fields = described_class["table"].select([Contact._id, Contact.context.sql("some sql")])._select_fields
        fields.size.should eq(2)
        fields[1].identifier.should eq("some sql")
      end
    end

    context "with block" do
      it "yield expression builder as current context and accepts array" do
        fields = described_class["table"].select { [_f1, Contact._id] }._select_fields
        fields.size.should eq(2)
        fields[0].field.should eq("f1")
        fields[0].table.should eq("table")
      end

      it "removes brackets from raw sql" do
        field = described_class["table"].select { [sql("f1")] }._select_fields[0]
        field.identifier.should eq("f1")
      end
    end
  end

  describe "#where" do
    it "allows to pass criteria and sets it via AND" do
      q1 = Factory.build_query
      c = Factory.build_criteria(field: "f1") & Factory.build_criteria(field: "f2")
      q1.where { c("f1") & c("f2") }
      q1.tree.to_s.should match(/tests\.f1 AND tests\.f2/)
    end
  end

  describe "#join" do
    it "adds inner join by default" do
      q1 = Factory.build_query
      q1.join(Address) { _test__id == _contact_id }
      q1._joins!.map(&.type).should eq([:inner])
    end

    context "with Query as a source" do
      it "creates proper join" do
        q = Factory.build_query
        q.join(Factory.build_query, "t1") { sql("true") }
        q._joins![0].as_sql.should match(/SELECT/m)
      end
    end

    context "with ModelQuery as a source" do
      it "creates proper join" do
        q = Factory.build_query
        q.join(Contact.where { _id == 2 }, "t1") { sql("true") }
        q._joins![0].as_sql.should match(/SELECT contacts/m)
      end
    end
  end

  describe "#laterla_join" do
    join_query = Contact.where { _id == 2 }

    it "adds inner join by default" do
      q1 = Factory.build_query
      q1.lateral_join(join_query, "t") { _test__id == _contact_id }
      q1._joins!.map(&.type).should eq([:inner])
    end

    it "builds laterla join" do
      q1 = Factory.build_query
      q1.lateral_join(join_query, "t") { _test__id == _contact_id }
      q1._joins!.map(&.class).should eq([Jennifer::QueryBuilder::LateralJoin])
    end

    context "with Query as a source" do
      it "creates proper join" do
        q = Factory.build_query
        q.lateral_join(Factory.build_query, "t1") { sql("true") }
        q._joins![0].as_sql.should match(/SELECT/m)
      end
    end

    context "with ModelQuery as a source" do
      it "creates proper join" do
        q = Factory.build_query
        q.lateral_join(join_query, "t1") { sql("true") }
        q._joins![0].as_sql.should match(/SELECT contacts/m)
      end
    end
  end

  describe "#left_join" do
    it "addes left join" do
      q1 = Factory.build_query
      q1.left_join(Address) { _test__id == _contact_id }
      q1._joins!.map(&.type).should eq([:left])
    end
  end

  describe "#right_join" do
    it "addes right join" do
      q1 = Factory.build_query
      q1.right_join(Address) { _test__id == _contact_id }
      q1._joins!.map(&.type).should eq([:right])
    end
  end

  describe "#having" do
    it "returns correct entities" do
      Factory.create_contact(name: "Ivan", age: 15)
      Factory.create_contact(name: "Max", age: 19)
      Factory.create_contact(name: "Ivan", age: 50)

      res = Contact.all.select("COUNT(id) as count, contacts.name").group("name").having { sql("COUNT(id)") > 1 }.pluck(:name)
      res.size.should eq(1)
      res[0].should eq("Ivan")
    end

    it "joins several having invocation with AND" do
      Contact.all.having { _id > 1 }.having { _id < 2 }._having!.as_sql.should eq("contacts.id > %s AND contacts.id < %s")
    end
  end

  describe "#delete" do
    it "deletes from db using existing conditions" do
      count = Contact.all.count
      c = Factory.create_contact(name: "Extra content")
      Contact.all.count.should eq(count + 1)
      described_class.new("contacts").where { _name == "Extra content" }.delete
      Contact.all.count.should eq(count)
    end
  end

  describe "#exists?" do
    it "returns true if there is such object with given condition" do
      Factory.create_contact(name: "Anton")
      described_class.new("contacts").where { _name == "Anton" }.exists?.should be_true
    end

    it "returns false if there is no such object with given condition" do
      Factory.create_contact(name: "Anton")
      described_class.new("contacts").where { _name == "Jhon" }.exists?.should be_false
    end
  end

  describe "#group" do
    context "with symbol" do
      it "creates criteria for given fields and current table" do
        fields = described_class["table"].group(:f1)._groups
        fields.size.should eq(1)
        fields[0].field.should eq("f1")
        fields[0].table.should eq("table")
      end
    end

    context "with symbol tuple" do
      it "adds all as criteria" do
        fields = described_class["table"].group(:f1, :f2)._groups
        fields.size.should eq(2)
        fields[0].field.should eq("f1")
        fields[1].field.should eq("f2")
      end
    end

    context "with criteria" do
      it "adds it to select fields" do
        fields = described_class["table"].group(Contact._id)._groups
        fields.size.should eq(1)
        fields[0].field.should eq("id")
        fields[0].table.should eq("contacts")
      end

      context "as raw sql" do
        it "removes brackets" do
          field = described_class["table"].group(Contact.context.sql("some sql"))._groups[0]
          field.identifier.should eq("some sql")
        end
      end
    end

    context "with block" do
      it "yield expression builder as current context and accepts array" do
        fields = described_class["table"].group { [_f1, Contact._id] }._groups
        fields.size.should eq(2)
        fields[0].field.should eq("f1")
        fields[0].table.should eq("table")
      end

      it "removes brackets from raw sql" do
        field = described_class["table"].group { [sql("f1")] }._groups[0]
        field.identifier.should eq("f1")
      end
    end
  end

  describe "#order" do
    context "with named tuple" do
      it "converts all keys to criterias" do
        orders = Contact.all.order(age: :desc, id: "asc")._order
        orders.size.should eq(2)
        orders = orders.keys
        orders[0].table.should eq("contacts")
        orders[0].field.should eq("age")
      end
    end

    context "with hash with string keys" do
      it "treats all keys as raw sql without brackets" do
        orders = Contact.all.order({"age" => :desc})._order
        orders.keys[0].is_a?(Jennifer::QueryBuilder::RawSql)
        orders.keys[0].identifier.should eq("age")
        orders.values[0].should eq("desc")
      end
    end

    context "with hash with symbol keys" do
      it "treats all keys as criterias" do
        orders = Contact.all.order({:age => :desc})._order.keys
        orders[0].identifier.should eq("contacts.age")
      end
    end

    context "wiht hash with criterias as keys" do
      it "adds them to pool" do
        orders = Contact.all.order({Contact._id => :desc})._order
        orders.keys[0].identifier.should eq("contacts.id")
      end

      it "marks raw sql not to use brackets" do
        orders = Contact.all.order({Contact.context.sql("raw sql") => :desc, Contact._id => "asc"})._order.keys
        orders[0].identifier.should eq("raw sql")
      end
    end

    context "with block" do
      it "marks raw sql not to use brackets" do
        orders = Contact.all.order { {sql("raw sql") => :desc, _id => "asc"} }._order.keys
        orders[0].identifier.should eq("raw sql")
      end
    end
  end

  describe "#reorder" do
    context "with named tuple" do
      it "converts all keys to criterias" do
        base_query = Contact.all.order(id: :desc)

        orders = base_query.reorder(age: :desc, id: "asc")._order
        orders.size.should eq(2)
        orders = orders.keys
        orders[0].table.should eq("contacts")
        orders[0].field.should eq("age")
      end
    end

    context "with hash with string keys" do
      it "treats all keys as raw sql without brackets" do
        base_query = Contact.all.order(id: :desc)
        orders = base_query.reorder({"age" => :desc})._order
        orders.keys[0].is_a?(Jennifer::QueryBuilder::RawSql)
        orders.keys[0].identifier.should eq("age")
        orders.values[0].should eq("desc")
      end
    end

    context "with hash with symbol keys" do
      it "treats all keys as criterias" do
        base_query = Contact.all.order(id: :desc)

        orders = base_query.reorder({:age => :desc})._order.keys
        orders[0].identifier.should eq("contacts.age")
      end
    end

    context "wiht hash with criterias as keys" do
      it "adds them to pool" do
        base_query = Contact.all.order(id: :desc)
        orders = base_query.reorder({Contact._id => :desc})._order
        orders.keys[0].identifier.should eq("contacts.id")
      end

      it "marks raw sql not to use brackets" do
        base_query = Contact.all.order(id: :desc)
        orders = base_query.reorder({Contact.context.sql("raw sql") => :desc, Contact._id => "asc"})._order.keys
        orders[0].identifier.should eq("raw sql")
      end
    end

    context "with block" do
      it "marks raw sql not to use brackets" do
        base_query = Contact.all.order(id: :desc)
        orders = base_query.reorder { {sql("raw sql") => :desc, _id => "asc"} }._order.keys
        orders[0].identifier.should eq("raw sql")
      end
    end
  end

  describe "#limit" do
    it "sets limit" do
      Contact.all.limit(2).to_sql.should match(/LIMIT 2/m)
    end
  end

  describe "#offset" do
    it "sets offset" do
      Contact.all.offset(2).to_sql.should match(/OFFSET 2/m)
    end
  end

  describe "#from" do
    it "accepts plain query" do
      select_clause(Factory.build_query(table: "contacts").from("select * from contacts where id > 2"))
        .should eq("SELECT contacts.*\nFROM ( select * from contacts where id > 2 ) ")
    end

    it "accepts query object" do
      select_clause(Factory.build_query(table: "contacts").from(Contact.where { _id > 2 }))
        .should eq("SELECT contacts.*\nFROM ( SELECT contacts.*\nFROM contacts\nWHERE contacts.id > %s\n ) ")
    end
  end

  describe "#increment" do
    it "accepts hash" do
      c = Factory.create_contact(name: "asd", gender: "male", age: 18)
      Contact.where { _id == c.id }.increment({:age => 2})
      Contact.find!(c.id).age.should eq(20)
    end

    it "accepts named tuple literal" do
      c = Factory.create_contact(name: "asd", gender: "male", age: 18)
      Contact.where { _id == c.id }.increment(age: 2)
      Contact.find!(c.id).age.should eq(20)
    end
  end

  describe "#decrement" do
    it "accepts hash" do
      c = Factory.create_contact(name: "asd", gender: "male", age: 20)
      Contact.where { _id == c.id }.decrement({:age => 2})
      Contact.find!(c.id).age.should eq(18)
    end

    it "accepts named tuple literal" do
      c = Factory.create_contact({:name => "asd", :gender => "male", :age => 20})
      Contact.where { _id == c.id }.decrement(age: 2)
      Contact.find!(c.id).age.should eq(18)
    end
  end

  describe "#results" do
    it "returns array of records" do
      r = Contact.all.results.should eq([] of Jennifer::Record)
    end
  end

  describe "#union" do
    it "adds query to own array of unions" do
      q = Jennifer::Query["table"]
      q.union(Jennifer::Query["table2"]).should eq(q)
      q._unions!.empty?.should be_false
    end
  end

  describe "#to_a" do
    context "none was called" do
      it "doesn't hit db and return empty array" do
        count = query_count
        result = Jennifer::Query["contacts"].none.to_a
        query_count.should eq(count)
        result.empty?.should be_true
      end
    end
  end

  describe "#_select_fields" do
    context "query has no specified select fields" do
      it "returns array with only star" do
        fields = Contact.all._select_fields
        fields.size.should eq(1)

        fields[0].is_a?(Jennifer::QueryBuilder::Star).should be_true
      end
    end

    context "query has specified fields" do
      it "returns specified fields" do
        fields = Contact.all.select { [_id, _age] }._select_fields
        fields.size.should eq(2)
        fields[0].field.should eq("id")
        fields[1].field.should eq("age")
      end
    end
  end

  describe "#each_result_set" do
    it "yields rows from result set" do
      Factory.create_contact(name: "a", age: 13)
      Factory.create_contact(name: "b", age: 14)

      i = 0
      Contact.all.each_result_set do |rs|
        rs.should be_a DB::ResultSet
        Contact.new(rs)
        i += 1
      end
      i.should eq(2)
    end
  end

  describe "#each" do
    it "yields each found row" do
      Factory.create_contact(name: "a", age: 13)
      Factory.create_contact(name: "b", age: 14)
      i = 13
      Contact.all.order(age: :asc).each do |c|
        c.age.should eq(i)
        i += 1
      end
      i.should eq(15)
    end
  end

  describe "#distinct" do
    it "adds DISTINC to SELECT clause" do
      Query["contacts"].select(:age).distinct.to_sql.should match(/SELECT DISTINCT contacts\.age/)
    end

    it "returns uniq rows" do
      Factory.create_contact(name: "a1")
      Factory.create_contact(name: "a2")
      Factory.create_contact(name: "a1")
      r = Contact.all.order(name: :asc).select(:name).distinct.results
      r.size.should eq(2)
      r.map(&.name).should eq(["a1", "a2"])
    end
  end

  describe "#find_records_by_sql" do
    query = <<-SQL
      SELECT contacts.*
      FROM contacts
    SQL

    it "builds all requested objects" do
      Factory.create_contact
      res = Query["contacts"].find_records_by_sql(query)
      res.size.should eq(1)
      res[0].id.nil?.should be_false
    end

    it "respects none method" do
      Factory.create_contact
      res = Query["contacts"].none.find_records_by_sql(query)
      res.size.should eq(0)
    end
  end

  describe "#find_in_batches" do
    query = Query["contacts"]

    context "with primary field" do
      context "as criteria" do
        pk = Factory.build_criteria(table: "contacts", field: "id")

        it "yields proper amount of records" do
          Factory.create_contact(3)
          executed = false
          query.find_in_batches(batch_size: 2, primary_key: pk) do |records|
            executed = true
            records.size.should eq(2)
            break
          end
          executed.should be_true
        end

        it "yields proper amount of times" do
          Factory.create_contact(3)
          yield_count = 0
          query.find_in_batches(batch_size: 2, primary_key: pk) do |records|
            yield_count += 1
          end
          yield_count.should eq(2)
        end

        it "use 'start' argument as start primary key value" do
          yield_count = 0
          ids = Factory.create_contact(3).map(&.id)
          query.find_in_batches(ids[1], 2, pk) do |records|
            yield_count += 1
            records[0].id.should eq(ids[1])
            records[1].id.should eq(ids[2])
          end
          yield_count.should eq(1)
        end
      end

      context "as string" do
        it "properly loads records" do
          Factory.create_contact(3)
          yield_count = 0
          query.find_in_batches(primary_key: "id", batch_size: 2) do |records|
            yield_count += 1
          end
          yield_count.should eq(2)
        end
      end
    end

    context "without primary key" do
      it "uses 'start' as a page number" do
        Factory.create_contact(3)
        yield_count = 0
        query.find_in_batches(1, 2) do |records|
          yield_count += 1
        end
        yield_count.should eq(1)
      end
    end
  end
end
