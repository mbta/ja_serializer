defmodule JaSerializer.Builder.RelationshipTest do
  use ExUnit.Case
  alias JaSerializer.Builder.Relationship
  alias JaSerializer.Relationship.HasMany
  alias JaSerializer.Builder.RelationshipTest.CommentSerializer

  defmodule ArticleSerializer do
    use JaSerializer

    def type, do: "articles"
    attributes([:title])

    has_many(
      :comments,
      serializer: CommentSerializer,
      include: true
    )
  end

  defmodule CommentSerializer do
    use JaSerializer
    def id(comment, _conn), do: comment.comment_id
    def type, do: "comments"
    location("/comments/:id")
    attributes([:body])
  end

  defmodule CommentWithArticleSerializer do
    use JaSerializer
    def id(comment, _conn), do: comment.comment_id
    def type, do: "comments"
    location("/comments/:id")
    attributes([:body])

    has_one(
      :article,
      serializer: ArticleSerializer,
      include: false,
      identifiers: :when_included
    )
  end

  defmodule CommentWithArticleIdentifiersSerializer do
    use JaSerializer

    has_one(
      :article,
      serializer: ArticleSerializer,
      identifiers: :always,
      include: false
    )
  end

  defmodule CommentWithArticlesForeignKeySerializer do
    use JaSerializer

    has_one(
      :article,
      serializer: ArticleSerializer,
      foreign_key: :story_id,
      identifiers: :always,
      include: false
    )
  end

  defmodule FooSerializer do
    use JaSerializer

    has_many(
      :bars,
      type: "bar",
      links: [
        self: "/foo/:id/relationships/bars",
        related: "/foo/:id/bars"
      ]
    )

    has_one(:baz, field: :baz_id, type: "baz")
    has_one(:qux, type: "qux")

    def bars(_, _), do: [1, 2, 3]

    def qux(%{quxes: [qux | _]}), do: qux
    def qux(_), do: nil
  end

  test "custom id def respected in relationship data" do
    c1 = %TestModel.CustomIdComment{comment_id: "c1", body: "c1"}
    c2 = %TestModel.CustomIdComment{comment_id: "c2", body: "c2"}
    a1 = %TestModel.Article{id: "a1", title: "a1", comments: [c1, c2]}

    context = %{data: a1, conn: %{}, serializer: ArticleSerializer, opts: []}
    primary_resource = JaSerializer.Builder.ResourceObject.build(context)

    %JaSerializer.Builder.ResourceObject{
      relationships: [%JaSerializer.Builder.Relationship{:data => rel_data}]
    } = primary_resource

    assert [_, _] = rel_data

    ids = Enum.map(rel_data, & &1.id)
    assert "c1" in ids
    assert "c2" in ids

    # Formatted
    json = JaSerializer.format(ArticleSerializer, a1)
    assert %{"relationships" => %{"comments" => comments}} = json["data"]
    assert [_, _] = comments["data"]

    formatted_ids = Enum.map(comments["data"], & &1["id"])
    assert "c1" in formatted_ids
    assert "c2" in formatted_ids
  end

  test "building a self link Relationship is possible along with the 'related'" do
    json = JaSerializer.format(FooSerializer, %{baz_id: 1, id: 1})
    rel_links = json["data"]["relationships"]["bars"]["links"]
    assert "/foo/1/relationships/bars" = rel_links["self"]
    assert "/foo/1/bars" = rel_links["related"]
  end

  test "building relationships from ids works" do
    json = JaSerializer.format(FooSerializer, %{baz_id: 1, id: 1})
    assert %{"relationships" => %{"bars" => bars, "baz" => baz}} = json["data"]
    assert baz["data"]["id"] == "1"
    assert [bar, _, _] = bars["data"]
    assert bar["id"] == "1"
  end

  test "the correct keys are filtered out with build" do
    json =
      JaSerializer.format(FooSerializer, %{baz_id: 1, id: 1}, %{},
        fields: %{"foo" => "bars"}
      )

    assert json["data"]["relationships"]["bars"]
    refute json["data"]["relationships"]["baz"]
  end

  test "identifiers are included if type passed in" do
    comments = %HasMany{
      type: "comment",
      data: [1, 2, 3]
    }

    context = %{conn: %{}, opts: []}
    rel = Relationship.build({:comments, comments}, context)
    assert [_ri1, _ri2, _ri3] = rel.data
  end

  test "identifiers are included if serializer is passed in and include is true" do
    comments = %HasMany{
      serializer: CommentSerializer,
      data: [1, 2, 3],
      include: true
    }

    context = %{conn: %{}, opts: []}
    rel = Relationship.build({:comments, comments}, context)
    assert [_ri1, _ri2, _ri3] = rel.data
  end

  test "identifiers are included if serializer is passed in & name is in the include param" do
    comments = %HasMany{
      serializer: CommentSerializer,
      data: [1, 2, 3],
      identifiers: :always
    }

    context = %{conn: %{}, opts: [include: [:comments]]}
    rel = Relationship.build({:comments, comments}, context)
    assert [_ri1, _ri2, _ri3] = rel.data
  end

  test "identifiers are included if the serializer is passed in & name is not in include parama & identifiers is always" do
    comments = %HasMany{
      serializer: CommentSerializer,
      data: [1, 2, 3],
      identifiers: :always
    }

    context = %{conn: %{}, opts: [include: [author: []]]}
    rel = Relationship.build({:comments, comments}, context)
    assert [_ri1, _ri2, _ri3] = rel.data
  end

  test "identifiers are not included if the serializer is passed in & name is not in include param & include is true & identifiers is when_included" do
    comments = %HasMany{
      serializer: CommentSerializer,
      identifiers: :when_included
    }

    context = %{conn: %{}, opts: [include: [:author]]}
    rel = Relationship.build({:comments, comments}, context)
    assert is_nil(rel.data)
  end

  test "identifiers are not included if the serializer is passed in, there are not in include params & indentifiers is when_included" do
    comments = %HasMany{
      serializer: CommentSerializer,
      identifiers: :when_included
    }

    context = %{conn: %{}, opts: []}
    rel = Relationship.build({:comments, comments}, context)
    assert rel.data == nil
  end

  test "skipping relationship building with `relationships: false`" do
    json =
      JaSerializer.format(
        FooSerializer,
        %{baz_id: 1, id: 1},
        %{},
        relationships: false
      )

    refute Map.has_key?(json["data"], "relationships")
  end

  test "can override default relationship function with one argument" do
    json = JaSerializer.format(FooSerializer, %{quxes: [1, 2, 3]})
    assert %{"relationships" => %{"qux" => qux}} = json["data"]
    assert qux == %{"data" => %{"id" => "1", "type" => "qux"}}
  end

  test "empty relationships are not included" do
    json =
      JaSerializer.format(
        CommentWithArticleSerializer,
        %{comment_id: 1, article: %{title: "title"}},
        %{}
      )

    refute Map.has_key?(json["data"], "relationships")
  end

  test "has_one identifiers are serialized when present" do
    json =
      JaSerializer.format(
        CommentWithArticleIdentifiersSerializer,
        %{id: 1, article_id: 1, article: %Ecto.Association.NotLoaded{}},
        %{}
      )

    article = get_in(json, ["data", "relationships", "article"])
    assert article == %{"data" => %{"id" => "1", "type" => "articles"}}
    refute Map.has_key?(json["data"], "included")
  end

  test "has_one identifiers are not serialized when nil" do
    json =
      JaSerializer.format(
        CommentWithArticleIdentifiersSerializer,
        %{id: 1, article_id: nil, article: %Ecto.Association.NotLoaded{}},
        %{}
      )

    article = get_in(json, ["data", "relationships", "article"])
    assert article == %{"data" => nil}
    refute Map.has_key?(json["data"], "included")
  end

  test "has_one identifiers are serialized when present using foreign_key" do
    json =
      JaSerializer.format(
        CommentWithArticlesForeignKeySerializer,
        %{id: 1, story_id: 1, article: %Ecto.Association.NotLoaded{}},
        %{}
      )

    article = get_in(json, ["data", "relationships", "article"])
    assert article == %{"data" => %{"id" => "1", "type" => "articles"}}
    refute Map.has_key?(json["data"], "included")
  end

  test "has_one raises exception when identifiers cannot be determined" do
    assert_raise JaSerializer.AssociationNotLoadedError, fn ->
      JaSerializer.format(
        CommentWithArticleIdentifiersSerializer,
        %{id: 1, article: %Ecto.Association.NotLoaded{}},
        %{}
      )
    end
  end
end
