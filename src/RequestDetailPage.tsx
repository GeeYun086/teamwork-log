import { FormEvent, useState } from 'react'
import { ArrowLeft, BriefcaseBusiness, Check, Clock3, Flag, MessageSquareText, Send, Trash2, Users } from 'lucide-react'

type RequestItem = { id: string; task_id: string | null; requester_id: string; assignee_id: string; body: string; priority: string; due_date: string | null; status: string; created_at: string }
type Member = { user_id: string; display_name: string }
type Task = { id: string; title: string; description?: string }
type CommentItem = { id: string; request_id: string; author_id: string; body: string; created_at: string }
type Props = { request: RequestItem; members: Member[]; tasks: Task[]; comments: CommentItem[]; currentUserId: string; canUpdateStatus: boolean; canDeleteRequest: boolean; onBack: () => void; onUpdateStatus: (status: string) => void; onDeleteRequest: () => void; onAddComment: (body: string) => void }

export default function RequestDetailPage({ request, members, tasks, comments, currentUserId, canUpdateStatus, canDeleteRequest, onBack, onUpdateStatus, onDeleteRequest, onAddComment }: Props) {
  const [comment, setComment] = useState('')
  const submitComment = (event: FormEvent) => { event.preventDefault(); const body = comment.trim(); if (!body) return; onAddComment(body); setComment('') }
  const person = (id: string) => members.find(member => member.user_id === id)?.display_name || '팀원'
  const task = tasks.find(item => item.id === request.task_id)
  return <div className="content request-detail-content">
    <div className="page-heading"><div><div className="eyebrow">REQUEST DETAILS</div><h1>수정 요청 상세</h1><p>요청 내용과 담당자, 진행 상태를 확인할 수 있어요.</p></div><button className="button outline" onClick={onBack}><ArrowLeft size={15}/> 요청 목록</button></div>
    <article className="panel request-detail-card">
      <div className="request-card-head"><span className={`priority-pill ${request.priority === '높음' ? 'high' : ''}`}><Flag size={13}/>{request.priority} 우선순위</span><span className={`request-state state-${request.status}`}>{request.status}</span></div>
      <div className="request-detail-task"><BriefcaseBusiness size={17}/><div><small>관련 업무</small><h2>{task?.title || '연결된 업무 없음'}</h2>{task?.description && <p>{task.description}</p>}</div></div>
      <section className="request-detail-body"><h3>구체적인 수정 내용</h3><p>{request.body}</p></section>
      <div className="request-detail-meta"><div><Users size={16}/><span><small>요청자</small><b>{person(request.requester_id)}</b></span></div><div><Users size={16}/><span><small>담당자</small><b>{person(request.assignee_id)}</b></span></div><div><Clock3 size={16}/><span><small>요청일</small><b>{new Date(request.created_at).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })}</b></span></div>{request.due_date && <div><Clock3 size={16}/><span><small>희망 완료일</small><b>{request.due_date}</b></span></div>}</div>
      {(canUpdateStatus || canDeleteRequest) && <div className="request-detail-actions">{canUpdateStatus && <div className="request-detail-status"><label htmlFor="request-detail-status">요청 상태</label><select id="request-detail-status" value={request.status} onChange={event => onUpdateStatus(event.target.value)}><option>보냄</option><option>확인함</option><option>진행 중</option><option>완료</option><option>보류</option></select>{request.assignee_id === currentUserId && request.status === '보냄' && <button className="button outline small" onClick={() => onUpdateStatus('확인함')}>확인했어요</button>}</div>}<div className="request-detail-action-buttons">{canUpdateStatus && request.status !== '완료' && <button className="button primary small" onClick={() => onUpdateStatus('완료')}><Check size={15}/> 완료 처리</button>}{canDeleteRequest && <button className="button outline danger-outline small" onClick={onDeleteRequest}><Trash2 size={14}/> 삭제</button>}</div></div>}
      <section className="request-comments"><div className="request-comments-heading"><h3><MessageSquareText size={17}/> 댓글</h3><span>{comments.length}개</span></div><div className="request-comment-list">{comments.map(item => <article className="request-comment" key={item.id}><div className="request-comment-top"><b>{person(item.author_id)}{item.author_id === currentUserId && <small>나</small>}</b><time>{new Date(item.created_at).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</time></div><p>{item.body}</p></article>)}{!comments.length && <p className="request-comment-empty">아직 댓글이 없어요. 진행 상황이나 확인 내용을 남겨보세요.</p>}</div><form className="request-comment-form" onSubmit={submitComment}><textarea value={comment} onChange={event => setComment(event.target.value)} maxLength={4000} placeholder="요청에 대한 댓글을 남기세요." rows={3}/><button className="button primary small" disabled={!comment.trim()}><Send size={14}/> 댓글 등록</button></form></section>
    </article>
  </div>
}
