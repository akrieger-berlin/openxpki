
Configuration of the Workflow Engine with UI
============================================

All files mentioned here are below the node ``workflow`` inside the realm configuration. Filenames are all lowercased.

Workflow Definitions
--------------------

Each workflow is represented by a file or directory structure below ``workflow.def.<name>``. The name of the file is equal to the internal name of the workflow. Each such file must have the following structure, not all attributes are mandatory or useful in all situations::

    head:
        label: The verbose name of the workflow, shown on the UI
        description: The verbose description of the workflow, shown on the UI
        prefix: internal short name, used to prefix the actions, must be unique
                Must not contain any other characters than [a-z0-9]

    state:
        name_of_state:  (used as literal name in the engine)
            autorun: 0/1
            autofail: 0/1
            label: visible name
            description: the text for the page head
            action:
              - name_of_action > state_on_success ? condition_name
              - name_of_other_action > other_state_on_success !condition_name
            hint:
                name_of_action: A verbose text shown aside of the button
                name_of_other_action: A verbose text shown aside of the button

    action:
        name_of_action: (as used above)
            label: Verbose name, shown as label on the button
            tooltip: Hint to show as tooltip on the button
            description: Verbose description, show on UI page
            class: Name of the implementation class
            abort: state to jump to on abort (UI button, optional) # not implemented yet
            resume: state to jump to on resume (after exception, optional) # not implemented yet
            validator:
              - name_of_validator (defined below)
            input:
              - name_of_field (defined below)
              - name_of_other_field
            param:
                key: value - passed as params to the action class

    field:
        field_name: (as used above)
            name: key used in context
            label: The fields label
            placeholder: Hint text shown in empty form elements
            tooltip: Text for "tooltip help"
            type:     Type of form element (default is input)
            required: 0|1
            default:  default value
            more_key: other_value  (depends on form type)

    validator:
        class: OpenXPKI::Server::Workflow::Validator::CertIdentifierExists
        param:
            emptyok: 1
        arg:
          - $cert_identifier


Note: All entity names must contain only letters (lower ascii), digits and the underscore.

Below is a simple, but working workflow config (no conditions, no validators, the global action is defined outside this file)::

    head:
        label: I am a Test
        description: This is a Workflow for Testing
        prefix: test

    state:
        INITIAL:
            label: initial state
            description: This is where everything starts
            action: run_test1 > PENDING

        PENDING:
            label: pending state
            description: We hold here for a while
            action: global_run_test2 > SUCCESS

        SUCCESS:
            label: finals state
            description: It's done - really!
            status:
                level: success
                message: This is shown as green status bar on top of the page

    action:
        run_test1:
        label: The first Action
        description: I am first!
        class: Workflow::Action::Null
        input: comment
        param:
            message: "Hi, I am a log message"

    field:
        comment: (as used above)
            name: comment
            label: Your Comment
            placeholder: Please enter a comment here
            tooltip: Tell us what you think about it!
            type: textarea
            required: 1
            default: ''


Workflow Head
^^^^^^^^^^^^^

States
^^^^^^

The ``action`` attribute is a list (or scalar) holding the action name and the
follow up state. Put the name of the action and the expected state on success,
seperated by the ``>`` sign (is greater than).

Action
^^^^^^


Field
^^^^^

*Select Field with options*

    type: select
    option:
        item:
          - unspecified
          - keyCompromise
          - CACompromise
          - affiliationChanged
          - superseded
          - cessationOfOperation
        label: I18N_OPENXPKI_UI_WORKFLOW_FIELD_REASON_CODE_OPTION

If the label tag is given (below option!), the values in the drop down are
i18n strings made from label + uppercase(key), e.g
I18N_OPENXPKI_UI_WORKFLOW_FIELD_REASON_CODE_OPTION_UNSPECIFIED

UI Rendering
------------

The UI uses information from the workflow definition to render display and input pages. There are two different kinds of pages, switches and inputs.

Action Switch Page
^^^^^^^^^^^^^^^^^^

Used when the workflow comes to a state with more than one possible action.

*headline*

Concated string from state.label + workflow.label

*descriptive intro*

String as defined in state.description, can contain HTML tags

*workflow context*

By default a plain dump of the context using key/values, array/hash values are converted to a html list/dd-list. You can define a custom output table with labels, formatted values and even links, etc - see the section "Workflow Output Formatting" fore details.

*button bar / simple layout*

One button is created for each available action, the button label is taken from action.label. The value of action.tooltip becomes a mouse-over label.

*button bar / advanced layout*

If you set the state.hint attribute, each button is drawn on its own row with a help text shown aside.

Form Input Page
^^^^^^^^^^^^^^^

Used when the workflow comes to a state where only one action is available or where one action was choosen.

*headline*

Concated string from action.label (if none is given: state.label ) + workflow.label

*descriptive intro*

String as defined in action.description, can contain HTML tags

*form fields*

The field itself is created from label, placeholder and tooltip. If at least one form field has the description attribute set,
an explanatory block for the fields is added to the bottom of the page.

Markup of Final States
^^^^^^^^^^^^^^^^^^^^^^

If the workflow is in a final state, the default is to render a colored
status bar on with a message that depends on the name of the state.
Recognized names are SUCCESS, CANCELED and FAILURE which generate a
green/yellow/red bar with a corresponding error message. The state name
NOSTATUS has no status bar at all.

If the state does not match one of those names, a yellow bar saying
"The workflow is in final state" is show.

To customize/suppress the status bar you can add level and message
to the state definition (see above).

Global Entities
---------------

You can define entities for action, condition and validator for global use in the corresponding files below ``workflow.global.``. The format is the same as described below, the "global_" prefix is added by the system.

Creating Macros (not implemented yet!)
--------------------------------------

If you have a sequence of states/actions you need in multiple workflows, you can
define them globally as macro. Just put the necessary state and action sections
as written above into a file below ``workflow.macros.<name>``. You need to have
one state named ``INITIAL`` and one ``FINAL``.

To reference such a macro, create an action in your main workflow and replace the
``class`` atttribute with ``macro``. Note that this is NOT an extension to the workflow
engine but only merges the definitions from the macro file with those of the current
workflow. After successful execution, the workflow will be in the state passed in the
``success`` attribute ofthe surrounding action.



