require "../spec_helper"

# TODO: add checking for log entries when we shouldn't hit db

describe Jennifer::QueryBuilder::ModelQuery do
  describe "#with" do
    it "addes to select clause given relation" do
      q1 = Contact.all.relation(:addresses)
      q1.with(:addresses)
      select_clause(q1).should match(/SELECT contacts\.\*, addresses\.\*/)
    end

    it "raises error if given relation is not exists" do
      q1 = Contact.all
      expect_raises(Jennifer::UnknownRelation, "Unknown relation for Contact: relation") do
        q1.with(:relation)
        select_clause(q1)
      end
    end

    it "raises error if given relation is not joined" do
      expect_raises(Jennifer::BaseException, /with should be called after correspond join: no such table/) do
        select_clause(Contact.all.with(:addresses))
      end
    end
  end

  describe "#eager_load" do
    it "loads relation as well" do
      c1 = Factory.create_contact(name: "asd")
      Factory.create_address(contact_id: c1.id, street: "asd st.")
      res = Contact.all.eager_load(:addresses).first!
      res.addresses[0].street.should eq("asd st.")
    end

    context "target class defines not all fields and has non strict mapping" do
      it "loads both target class fields and included ones" do
        contacts = Factory.create_contact(3)
        ids = contacts.map(&.id)
        Factory.create_address(contact_id: contacts[0].id)
        res = ContactWithDependencies.all.eager_load(:addresses).where { _id.in(ids) }.order(id: :asc).to_a
        res.size.should eq(3)
        res[0].addresses.size.should eq(1)
        res[0].name.nil?.should be_false
      end
    end

    context "related model has own request" do
      # TODO: move it to SqlGenerator
      it "it generates proper request" do
        contact = Factory.create_contact
        query = Contact.all.eager_load(:main_address)
        Jennifer::Adapter::SqlGenerator.select(query).should match(/addresses\.main/)
      end
    end

    pending "with aliases" do
    end
  end

  describe "#relation" do
    # TODO: refactor this bad test - this should be tested under sql generating process
    it "makes join using relation scope" do
      ::Jennifer::Adapter::SqlGenerator
        .select(Contact.all.relation(:addresses))
        .should match(/LEFT JOIN addresses ON addresses.contact_id = contacts.id/)
    end
  end

  describe "#destroy" do
    pending "add" do
    end
  end

  describe "#first" do
    it "returns first record" do
      c1 = Factory.create_contact(age: 15)
      c2 = Factory.create_contact(age: 15)

      r = Contact.all.first
      r.not_nil!.id.should eq(c1.id)
    end

    it "returns nil if there is no such records" do
      Contact.all.first.should be_nil
    end
  end

  describe "#first!" do
    it "returns first record" do
      c1 = Factory.create_contact(age: 15)
      c2 = Factory.create_contact(age: 15)

      r = Contact.all.first!
      r.id.should eq(c1.id)
    end

    it "raises error if there is no such records" do
      expect_raises(Jennifer::RecordNotFound) do
        Contact.all.first!
      end
    end
  end

  describe "#last" do
    it "inverse all orders" do
      c1 = Factory.create_contact(age: 15)
      c2 = Factory.create_contact(age: 16)

      r = Contact.all.order(age: :desc).last!
      r.id.should eq(c1.id)
    end

    it "add order by primary key if no order was specified" do
      c1 = Factory.create_contact(age: 15)
      c2 = Factory.create_contact(age: 16)

      r = Contact.all.last!
      r.id.should eq(c2.id)
    end
  end

  describe "#pluck" do
    context "given list of attributes" do
      it "returns array of arrays" do
        Factory.create_contact(name: "a", age: 13)
        Factory.create_contact(name: "b", age: 14)
        res = Contact.all.pluck(:name, :age)
        res.size.should eq(2)
        res[0][0].should eq("a")
        res[1][1].should eq(14)
      end
    end

    context "given one argument" do
      it "correctly extracts json" do
        Factory.create_address(details: JSON.parse({:city => "Duplin"}.to_json))
        Address.all.pluck(:details)[0].should be_a(JSON::Any)
      end

      it "accepts plain sql" do
        Factory.create_contact(name: "a", age: 13)
        res = Contact.all.select("COUNT(id) + 1 as test").pluck(:test)
        res[0].should eq(2)
      end

      pending "properly works with #with" do
      end
    end

    context "given array of attributes" do
      it "returns array of arrays" do
        Factory.create_contact(name: "a", age: 13)
        Factory.create_contact(name: "b", age: 14)
        res = Contact.all.pluck([:name, :age])
        res.size.should eq(2)
        res[0][0].should eq("a")
        res[1][1].should eq(14)
      end
    end
  end

  describe "#update" do
    it "updates given fields in all matched rows" do
      Factory.create_contact(age: 13, name: "a")
      Factory.create_contact(age: 14, name: "a")
      Factory.create_contact(age: 15, name: "a")

      Contact.where { _age < 15 }.update({:age => 20, :name => "b"})
      Contact.where { (_age == 20) & (_name == "b") }.count.should eq(2)
    end
  end

  describe "#select_args" do
    it "returns array of join and condition args" do
      Contact.where { _id == 2 }.join(Address) { _name == "asd" }.select_args.should eq(db_array("asd", 2))
    end
  end

  describe "#to_a" do
    it "retruns array of models" do
      Factory.create_contact(name: "a", age: 13)
      Factory.create_contact(name: "b", age: 14)
      res = Contact.all.to_a

      res.should be_a Array(Contact)
      res.size.should eq(2)
    end

    context "with nested objects" do
      it "builds nested objects" do
        c2 = Factory.create_contact(name: "b")
        p = Factory.create_passport(contact_id: c2.id, enn: "12345")
        res = Passport.all.join(Contact) { _id == _passport__contact_id }.with(:contact).first!

        res.contact!.name.should eq("b")
      end

      context "none was called" do
        it "doesn't hit db and return empty array" do
          count = query_count
          result = Contact.all.eager_load(:addresses).none.to_a
          query_count.should eq(count)
          result.empty?.should be_true
        end
      end

      context "when some records have no nested objects" do
        it "correctly build nested objects" do
          c1 = Factory.create_contact(name: "a")
          c2 = Factory.create_contact(name: "b")

          a1 = Factory.create_address(street: "a1 st.", contact_id: c1.id)
          a2 = Factory.create_address(street: "a2 st.", contact_id: c1.id)

          p = Factory.create_passport(contact_id: c2.id, enn: "12345")

          res = Contact.all.left_join(Address) { _contact_id == _contact__id }
                           .left_join(Passport) { _contact_id == _contact__id }
                           .order(id: :asc)
                           .with(:addresses, :passport).to_a

          res.size.should eq(2)

          res[0].addresses.size.should eq(2)
          res[1].addresses.size.should eq(0)
          res[0].passport.should be_nil
        end
      end

      context "retrieving several relation from same table" do
        it "uses auto aliasing" do
          c1 = Factory.create_contact(name: "a")
          c2 = Factory.create_contact(name: "b")

          a1 = Factory.create_address(main: false, contact_id: c1.id)
          a2 = Factory.create_address(main: false, contact_id: c1.id)
          a3 = Factory.create_address(main: true, contact_id: c1.id)

          q = Contact.all.eager_load(:addresses, :main_address)
          r = q.to_a
          r.size.should eq(2)
          r[0].addresses.size.should eq(3)
          r[0].main_address.nil?.should be_false
        end
      end
    end

    context "with includes" do
      it "loads all preloaded relations" do
        contacts = Factory.create_contact(3)
        a1 = Factory.create_address(contact_id: contacts[0].id)
        a2 = Factory.create_address(contact_id: contacts[1].id)
        f = Factory.create_facebook_profile(contact_id: contacts[1].id)
        res = Contact.all.includes(:addresses, :facebook_profiles).where { _id.in(contacts[0..1].map(&.id)) }.to_a

        res.size.should eq(2)
        match_array(res[0].addresses.map(&.id), [a1.id])
        match_array(res[1].addresses.map(&.id), [a2.id])
        match_array(res[1].facebook_profiles.map(&.id), [f.id])

        res[0].facebook_profiles.empty?.should be_true
      end
    end

    context "none was called" do
      it "doesn't hit db and return empty array" do
        count = query_count
        result = Jennifer::Query["contacts"].none.to_a
        query_count.should eq(count)
        result.empty?.should be_true
      end
    end
  end

  describe "#includes" do
    it "doesn't add JOIN condition" do
      Contact.all.includes(:address)._joins.nil?.should be_true
    end
  end

  describe "#_select_fields" do
    context "query has no specified select fields" do
      context "has eager loaded relations" do
        subject = Contact.all.eager_load(:addresses)._select_fields

        it "includes own star criteria" do
          subject.any? { |e| e.table == "contacts" && e.field == "*" }.should be_true
        end

        it "includes all mentioned relation star criterias" do
          subject.any? { |e| e.table == "addresses" && e.field == "*" }.should be_true
        end
      end

      it "returns only own star riteria" do
        fields = Contact.all._select_fields
        fields.size.should eq(1)

        fields[0].is_a?(Jennifer::QueryBuilder::Star).should be_true
        fields[0].table.should eq("contacts")
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

  describe "#find_by_sql" do
    query = <<-SQL
      SELECT contacts.*
      FROM contacts
    SQL

    it "builds all requested objects" do
      Factory.create_contact
      res = Contact.all.find_by_sql(query)
      res.size.should eq(1)
      res[0].id.nil?.should be_false
    end

    it "raises exception if not all required fields are listed in the select clause" do
      Factory.create_contact
      _query = <<-SQL
        SELECT id
        FROM contacts
      SQL
      expect_raises(Jennifer::BaseException, /includes only/) do
        res = Contact.all.find_by_sql(_query)
      end
    end

    it "respects none method" do
      Factory.create_contact
      res = Contact.all.none.find_by_sql(query)
      res.size.should eq(0)
    end

    it "preloads related objects if given" do
      c = Factory.create_contact
      Factory.create_address(contact_id: c.id)
      executed_query_count = query_count
      res = Contact.all.includes(:addresses).find_by_sql(query)
      (query_count - executed_query_count).should eq(2)
      res.size.should eq(1)
      res[0].addresses.size.should eq(1)
      (query_count - executed_query_count).should eq(2)
    end
  end

  describe "#find_in_batches" do
    it "loads in batches without specifying primary key" do
      ids = Factory.create_contact(3).map(&.id)
      yield_count = 0
      Contact.all.find_in_batches(ids[1], 2) do |records|
        yield_count += 1
        records[0].id.should eq(ids[1])
        records[1].id.should eq(ids[2])
      end
      yield_count.should eq(1)
    end
  end

  context "complex query example" do
    postgres_only do
      it "allows custom select with crouping" do
        Factory.create_contact
        Contact
          .all
          .select { [sql("count(*)").alias("stat_count"), sql("date_trunc('year', created_at)").alias("period")] }
          .group("period")
          .order({"period" => :desc})
          .results.size.should eq(1)
      end
    end
  end
end
