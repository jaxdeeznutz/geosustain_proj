"""Role-bound web workflow endpoints; legacy analysis APIs remain compatible."""
from datetime import date
from typing import Literal
from fastapi import Depends, HTTPException, Query
from pydantic import BaseModel, Field, StrictBool
import operator_workflow as workflow
import database as db
from contextlib import closing


class Decision(BaseModel):
    status: Literal['verified','rejected','needs_information']
    version: int = Field(ge=1)
    notes: str = Field('',max_length=500)
    reason: str = Field('',max_length=80)
    checklist: dict[str,StrictBool] = Field(default_factory=dict)


class Response(BaseModel):
    session_id: int = Field(gt=0)
    version: int = Field(ge=1)
    notes: str = Field(min_length=1,max_length=500)


class Note(BaseModel):
    notes: str = Field(min_length=1,max_length=500)


class Followup(BaseModel):
    title: str = Field(min_length=1,max_length=160)
    due_on: date


def install(app,get_user,require_planner):
    def filters(q: str=Query('',max_length=160),place: str=Query('',max_length=120),
                start: date|None=None,end: date|None=None):
        if start and end and start>end:raise HTTPException(422,'Start date must precede end date.')
        return dict(q=q,place=place,start=start,end=end)

    @app.get('/api/operator/inbox')
    def inbox(planner=Depends(require_planner),f=Depends(filters),
              status: str=Query('pending',pattern='^(all|pending|needs_information|verified|rejected)$'),
              offset: int=Query(0,ge=0),limit: int=Query(20,ge=1,le=100),sort: str=Query('oldest',pattern='^(oldest|newest)$'),
              view:str=Query('all',pattern='^(all|preliminary|reviewed_week|followups_due)$')):
        return workflow.inbox(status=status,offset=offset,limit=limit,sort=sort,view=view,**f)

    @app.get('/api/operator/map')
    def map_records(planner=Depends(require_planner),f=Depends(filters),
              status: str=Query('all',pattern='^(all|pending|needs_information|verified|rejected)$'),
              offset: int=Query(0,ge=0),limit: int=Query(50,ge=1,le=100),
              sort: str=Query('oldest',pattern='^(oldest|newest)$'),
              west: float|None=Query(None,ge=-180,le=180,allow_inf_nan=False),
              south: float|None=Query(None,ge=-90,le=90,allow_inf_nan=False),
              east: float|None=Query(None,ge=-180,le=180,allow_inf_nan=False),
              north: float|None=Query(None,ge=-90,le=90,allow_inf_nan=False)):
        bounds=(west,south,east,north)
        if any(v is not None for v in bounds) and any(v is None for v in bounds):raise HTTPException(422,'Supply all four map bounds.')
        return workflow.inbox(status=status,offset=offset,limit=limit,sort=sort,map_view=True,bounds=bounds if west is not None else None,**f)

    @app.get('/api/operator/overview')
    def overview(planner=Depends(require_planner),f=Depends(filters)):
        return workflow.overview(**f)

    @app.get('/api/operator/cases/by-session/{session_id}')
    def by_session(session_id:int,planner=Depends(require_planner)):
        with closing(db.get_conn()) as conn,conn.cursor() as cur:
            cur.execute('SELECT case_id FROM review_case_revisions WHERE session_id=%s',(session_id,));row=cur.fetchone()
        if not row:raise HTTPException(404,'Submitted review case not found.')
        return workflow.detail(row['case_id'])

    @app.get('/api/operator/cases/{case_id}')
    def detail(case_id:int,planner=Depends(require_planner)):
        return workflow.detail(case_id)

    @app.get('/api/operator/cases/{case_id}/revisions/{session_id}')
    def revision(case_id:int,session_id:int,planner=Depends(require_planner)):
        data=workflow.detail(case_id)
        if session_id not in [r['session_id'] for r in data['revisions']]:raise HTTPException(404,'Revision not found.')
        return db.get_user_analysis(data['case']['owner_id'],session_id)

    @app.post('/api/operator/cases/{case_id}/decision')
    def decide(case_id:int,body:Decision,planner=Depends(require_planner)):
        return workflow.decide(case_id,planner['id'],body.status,body.version,body.notes,body.reason,body.checklist)

    @app.post('/api/operator/cases/{case_id}/notes')
    def note(case_id:int,body:Note,planner=Depends(require_planner)):
        return workflow.add_note(case_id,planner['id'],body.notes)

    @app.post('/api/operator/cases/{case_id}/followups')
    def followup(case_id:int,body:Followup,planner=Depends(require_planner)):
        if not body.title.strip():raise HTTPException(422,'Add a task title.')
        return workflow.followup(case_id,planner['id'],body.title,body.due_on)

    @app.post('/api/operator/cases/{case_id}/followups/{followup_id}/complete')
    def complete(case_id:int,followup_id:int,planner=Depends(require_planner)):
        return workflow.followup(case_id,planner['id'],'',date.today(),followup_id)

    @app.get('/api/mobile/review-cases')
    def owned_cases(user=Depends(get_user),offset:int=Query(0,ge=0),limit:int=Query(20,ge=1,le=100)):
        with closing(db.get_conn()) as conn,conn.cursor() as cur:
            cur.execute('''SELECT c.id AS case_id,c.status,c.version,c.current_session_id,c.farm_id,c.updated_at,
                s.farm_name_snapshot AS farm_name FROM review_cases c JOIN analysis_sessions s ON s.id=c.current_session_id
                WHERE c.owner_id=%s ORDER BY c.updated_at DESC,c.id DESC LIMIT %s OFFSET %s''',(user['id'],limit+1,offset))
            rows=[dict(r) for r in cur.fetchall()]
        return {'cases':rows[:limit],'has_more':len(rows)>limit}

    @app.get('/api/mobile/review-cases/{case_id}')
    def owned_detail(case_id:int,user=Depends(get_user)):
        return workflow.detail(case_id,user['id'])

    @app.get('/api/mobile/review-cases/{case_id}/candidates')
    def candidates(case_id:int,user=Depends(get_user)):
        return {'analyses':workflow.candidates(case_id,user['id'])}

    @app.post('/api/mobile/review-cases/{case_id}/resubmit')
    def resubmit(case_id:int,body:Response,user=Depends(get_user)):
        if user.get('role')!='farmer':raise HTTPException(403,'Farmer account required for resubmission.')
        return workflow.resubmit(case_id,user['id'],body.session_id,body.version,body.notes)
